# k8s中部署Kafka-eagle
简介
kafka eagle（kafka鹰） 是一款由国内公司开源的Kafka集群监控系统，可以用来监视kafka集群的broker状态、Topic信息、IO、内存、consumer线程、偏移量等信息，并进行可视化图表展示。独特的KQL还可以通过SQL在线查询kafka中的数据。
1.下载kafka-eagle镜像
docker pull registry.cn-shanghai.aliyuncs.com/c-things/kafka-eagle:2.1.0
2. kafka-eagle数据存储
2.1 Sqlite；
kafka-eagle镜像中已安装sqlite，默认使用sqlite；
2.2 MySQL;
K8s中部署mysql：
1). 创建my.cnf配置文件
使用configMap存储mysql配置，vim mysql-config.yaml:
apiVersion: v1
kind: ConfigMap
metadata:
  name: mysql-ke-cnf
  namespace: default
data:
  my.cnf: |-
    [client]
    default-character-set=utf8
    [mysql]
    default-character-set=utf8
    [mysqld]
    init_connect='SET collation_connection = utf8_unicode_ci'
    init_connect='SET NAMES utf8'
    character-set-server=utf8
    collation-server=utf8_unicode_ci
    skip-character-set-client-handshake
    skip-name-resolve
    server_id=1
    log-bin=mysql-bin
    read-only=0
    replicate-ignore-db=mysql
    replicate-ignore-db=sys
    replicate-ignore-db=information_schema
    replicate-ignore-db=performance_schema

2). 配置mysql密码
使用Secret配置，也可以明文通过env配置，vim mysql-secret.yaml:
apiVersion: v1
kind: Secret
metadata:
  name: mysql-ke-secret
  namespace: default
type: Opaque
data:
  MYSQL_ROOT_PASSWORD: bWRiMTIzNDU2  #密码echo -n 'mdb123456' | base64结果

注：密码mdb123456 采用base64编码
echo -n 'mdb123456' | base64

3). 配置mysql存储
本文使用本地存储local-storage创建PV,PVC，vim mysql-pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: mysql-pv-ke
spec:
  capacity:
    storage: 40Gi 
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Delete
  storageClassName: local-storage
  local:
    path: /home/pv/mysql
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - cpu05
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
    name: mysql-pv-ke
    namespace: default
spec:
    storageClassName: local-storage
    accessModes: 
      - ReadWriteOnce
    resources:
        requests:
            storage: 40Gi

注：需要根据预先分配主机在，本地主机创建挂载目录
例如：主机：cpu05 
      目录：/home/pv/mysql

4). 创建有状态mysql及对外服务
使用StatefulSets、Headless、NodePort创建服务及对外服务暴露，
vim mysql-ss-svc.yaml
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  namespace: default
  labels:
    app: mysql-ke
  name: mysql-ke
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mysql-ke
  template:
    metadata:
      labels:
        app: mysql-ke
    spec:
      containers:
        - name: mysql-ke
          imagePullPolicy: IfNotPresent
          resources:
            requests:
              cpu: 500m
              memory: 1024Mi
            limits:
              cpu: '4'
              memory: 8096Mi
          image: 'mysql:5.7'
          ports:
            - name: tcp-3306
              protocol: TCP
              containerPort: 3306
          env:
            - name: MYSQL_DATABASE
              value: ke
            - name: MYSQL_USER
              value: ke
            - name: MYSQL_PASSWORD
              value: pwd123456
            - name: MYSQL_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mysql-ke-secret
                  key: MYSQL_ROOT_PASSWORD
          volumeMounts:
            - name: mysql-cnf
              mountPath: /etc/mysql/conf.d
            - name: mysql-data
              mountPath: /var/lib/mysql
      serviceAccount: default
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchLabels:
                    app: mysql-ke
                topologyKey: kubernetes.io/hostname
      initContainers: []
      imagePullSecrets: null
      volumes:
        - name: mysql-cnf            #映射configMap信息
          configMap:
            name: mysql-ke-cnf
            items:
              - key: my.cnf
                path: my.cnf
        - name: mysql-data    #映射pvc信息
          persistentVolumeClaim:
            claimName: mysql-pv-ke
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 0
  serviceName: mysql-ke

---

apiVersion: v1
kind: Service
metadata:
  namespace: default
  labels:
    app: mysql-ke
  name: mysql-ke
spec:
  sessionAffinity: ClientIP
  selector:
    app: mysql-ke
  ports:
    - name: tcp-3306
      protocol: TCP
      port: 3306
      targetPort: 3306
  clusterIP: None
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 10800
---

apiVersion: v1
kind: Service
metadata:
  name: mysql-ke-client
  labels:
    app: mysql-ke
  namespace: default
spec:
  selector:
    app: mysql-ke
  type: NodePort
  ports:
    - name: ''
      port: 3306
      protocol: TCP
      targetPort: 3306
      nodePort: 30306  #指定主机任意端口30000-32767
  sessionAffinity: None

5). 创建并启动用。
kubectl apply -f mysql-config.yaml
kubectl apply -f mysql-secret.yaml
kubectl apply -f mysql-pv.yaml
kubectl apply -f mysql-ss-svc.yaml
检查服务是否正常：
[root@localhost kafka]# kubectl get pods,svc,pv,pvc


远程连接验证：
mysql -h ip -P 30306 -uke -ppwd123456


3. 部署kafka-eagle
1). 修改system-config.properties文件：（根据实际修改）
vim system-config.properties
######################################
# multi zookeeper & kafka cluster list
# Settings prefixed with 'kafka.eagle.' will be deprecated, use 'efak.' instead
######################################
efak.zk.cluster.alias=cluster1
cluster1.zk.list=kafka-zookeeper-0.kafka-zookeeper-headless:2181,kafka-zookeeper-1.kafka-zookeeper-headless:2181,kafka-zookeeper-2.kafka-zookeeper-headless:2181
#cluster2.zk.list=xdn10:2181,xdn11:2181,xdn12:2181

######################################
# zookeeper enable acl
######################################
cluster1.zk.acl.enable=false
cluster1.zk.acl.schema=digest
cluster1.zk.acl.username=test
cluster1.zk.acl.password=test123

######################################
# broker size online list
######################################
cluster1.efak.broker.size=20

######################################
# zk client thread limit
######################################
kafka.zk.limit.size=16

######################################
# EFAK webui port
######################################
efak.webui.port=8048

######################################
# EFAK enable distributed
######################################
efak.distributed.enable=false
efak.cluster.mode.status=master
efak.worknode.master.host=localhost
efak.worknode.port=8085

######################################
# kafka jmx acl and ssl authenticate
######################################
cluster1.efak.jmx.acl=false
cluster1.efak.jmx.user=keadmin
cluster1.efak.jmx.password=keadmin123
cluster1.efak.jmx.ssl=false
cluster1.efak.jmx.truststore.location=/data/ssl/certificates/kafka.truststore
cluster1.efak.jmx.truststore.password=ke123456

######################################
# kafka offset storage
######################################
cluster1.efak.offset.storage=kafka
#cluster2.efak.offset.storage=zk

######################################
# kafka jmx uri
######################################
cluster1.efak.jmx.uri=service:jmx:rmi:///jndi/rmi://%s/jmxrmi

######################################
# kafka metrics, 15 days by default
######################################
efak.metrics.charts=true
efak.metrics.retain=15

######################################
# kafka sql topic records max
######################################
efak.sql.topic.records.max=5000
efak.sql.topic.preview.records.max=10

######################################
# delete kafka topic token
######################################
efak.topic.token=keadmin

######################################
# kafka sasl authenticate
######################################
cluster1.efak.sasl.enable=false
cluster1.efak.sasl.protocol=SASL_PLAINTEXT
cluster1.efak.sasl.mechanism=SCRAM-SHA-256
#cluster1.efak.sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="kafka" password="kafka-eagle";
cluster1.kafka.eagle.sasl.jaas.config=kafka_client_jaas.conf

cluster1.efak.sasl.client.id=
cluster1.efak.blacklist.topics=
cluster1.efak.sasl.cgroup.enable=false
cluster1.efak.sasl.cgroup.topics=

######################################
# kafka ssl authenticate
######################################

######################################
# kafka sqlite jdbc driver address
######################################
#efak.driver=org.sqlite.JDBC
#efak.url=jdbc:sqlite:/hadoop/kafka-eagle/db/ke.db
#efak.username=root
#efak.password=www.kafka-eagle.org

######################################
# kafka mysql jdbc driver address
######################################
efak.driver=com.mysql.cj.jdbc.Driver
efak.url=jdbc:mysql:// mysql-ke-0.mysql-ke.default.svc.cluster.local:3306/ke?useUnicode=true&characterEncoding=UTF-8&zeroDateTimeBehavior=convertToNull
efak.username=ke
efak.password=pwd123456
 
2). 编辑kafka-eagle的deplyment文件：
vim kafka-eagle.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-eagle
  namespace: default
spec:
  progressDeadlineSeconds: 600
  replicas: 1
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      workload.user.cattle.io/workloadselector: deployment-kafka-eagle
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
    type: RollingUpdate
  template:
    metadata:
      labels:
        workload.user.cattle.io/workloadselector: deployment-kafka-eagle
    spec:
      containers:
      - image: registry.cn-shanghai.aliyuncs.com/c-things/kafka-eagle:2.1.0
        imagePullPolicy: Always
        name: kafka-eagle
        ports:
        - containerPort: 8048
          name: 8048tcp01
          protocol: TCP
        resources: {}
        securityContext:
          allowPrivilegeEscalation: false
          privileged: false
          procMount: Default
          readOnlyRootFilesystem: false
          runAsNonRoot: false
        stdin: true
        terminationMessagePath: /dev/termination-log
        terminationMessagePolicy: File
        tty: true
        volumeMounts:
        - mountPath: /opt/kafka-eagle/conf
          name: conf
      dnsPolicy: ClusterFirst
      restartPolicy: Always
      schedulerName: default-scheduler
      securityContext: {}
      terminationGracePeriodSeconds: 30
      volumes:
      - configMap:
          defaultMode: 256
          name: kafka-eagle-config
          optional: false
        name: conf
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-eagle-client
  namespace: default
spec:
  type: NodePort
  ports:
    - port: 8048
      targetPort: 8048
      nodePort: 30048
  selector:
    workload.user.cattle.io/workloadselector: deployment-kafka-eagle
3). 配置登录账户密码
vim kafka_client_jaas.conf
KafkaClient {
  org.apache.kafka.common.security.plain.PlainLoginModule required
  username="admin"
  password="admin-secret";
};
4). 分别执行以下命令完成部署:
创建configmap：
kubectl create configmap kafka-eagle-config -n default --from-file=kafka_client_jaas.conf \
--from-file=system-config.properties
部署kafka-eagle：
kubectl apply -f kafka-eagle.yml
4. 浏览器访问
浏览器输入: http://ip:30048
测试环境：http://10.126.144.203:30048/
 
账号:admin 密码:123456

http://www.kafka-eagle.org/articles/docs/quickstart/dashboard.html


