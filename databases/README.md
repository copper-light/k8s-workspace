# 쿠버네티스에서 데이터베이스 유형의 서비스 배포하기
쿠버네티스의 일반적인 특성상 Pod가 재기동될 때 항상 같은 노드에서 실행을 보장하지 않습니다. 따라서, 데이터베이스처럼 상태 및 데이터가 유지되어야하는 서비스 같은 경우 Pod가 재기동되더라도 항상 같은 노드에 실행시킬 수 있는 방안이 필요합니다. 이를 위하여 쿠버네티스에서는 제공하는 배포 리소스가 **StatefulSet** 입니다. Pod의 배포를 위하여 추상화한 상위 개념으로 서비스 운영을 위한 각종 설정 기능을 가지고 있습니다. 본 템플릿에서는 실제 운영을 위한 설정에 대한 생략하고 배포 관점에서 최대한 간단한 구성으로 작성하였습니다.
  
## 현재 구성된 DB 목록
- MariaDB
- MySQL
- PostgreSQL
- MongoDB
- Altibase
  
## 기본 PersistentVolume 설정

본 템플릿에서는 외부 플러그인의 개념과 같은 커스텀 리소스 [LocalPathProvisioner](https://github.com/rancher/local-path-provisioner)를 **Local-StorageClass**라는 이름으로 구현하였고 이를 통하여 PersistentVolume(이하 PV)가 자동 생성되로록 구성하였기 때문에 PV를 직접 생성할 필요 없습니다.  
주의 사항으로는 LocalPathProvisioner은 현재 ReclaimPolicy가 Delete로 설정되어있으므로 바인딩된 PersistentVolumeClaim(이하 PVC)이 삭제될 경우 PV와 물리 스토리지의 데이터도 같이 삭제됩니다. 이러한 설정 때문에 혹시 모를 실수를 예방하기 위하여 StatefulSet과 PVC 배포 파일을 분리하여 작성하였습니다.
  
만약, ReclaimPolicy를 변경하고자 한다면 직접 PV를 생성하고 PVC를 바인딩하는 것을 권장합니다.
  
## 데이터베이스 배포
세부 설정을 제외한 서비스 배포 방법은 모든 DB가 동일하므로 본 설명에서는 MariaDB 를 기준으로 설명합니다.


### 1. Namespace 생성
---
리소스 관리의 편의성을 위하여 Namespace 를 생성하고 리소스를 생성하는 것을 권장합니다.  
튜토리얼 예시로 **test-dev**로 Namespace를 생성하여 진행합니다.
  
- Namespace 생성
```bash
$ kubectl create ns test-dev
namespace/test-dev created
```
  
- 생성된 Namespace 조회
```bash
$ kubectl get ns test-dev
NAME        STATUS   AGE
test-dev    Active   4h18m
```
  
### 2. 관리자 계정의 비밀번호를 위한 Secret 생성
---
쿠버네티스에서 계정 비밀번호나 인증서와 같은 보안이 필요한 요소들은 'Secret' 리소스로 관리하는 것을 권장합니다. Secret으로 만든 데이터는 Pod에서 Volume 으로 마운트하거나 시스템 환경변수로 불러와 활용하는 것이 가능합니다. 일반적으로 도커 이미지로 제공되는 서비스들은 환경변수를 통하여 시스템 관리자의 초기 비밀번호를 세팅하므로 본 템플릿에서도 Secret으로 만든 초기 비밀번호를 Pod의 환경변수로 전달하도록 작성하였습니다. 또한 모든 DB 서비스들이 같은 Secret을 공유하도록 설정되어 있으므로 참고바랍니다.
  
아래 명령어를 입력하여 Secret을 생성할 수 있습니다. 
본 명령어는 예시이므로 **'1234!'** 부분을 원하는 비밀번호로  변경하여 입력하면 됩니다.
  
- 비밀번호 값을 넣은 Secret 생성
```bash
$ kubectl create secret generic database-secret -n test-dev --from-literal=root-password='1234!'
secret/database-secret created
```
  
- 생성된 Secret 조회
```bash
$ kubectl describe secret database-secret -n test-dev
Name:         database-secret
Namespace:    test-dev
Labels:       <none>
Annotations:  <none>

Type:  Opaque

Data
====
root-password:  11 bytes
```
  
- DB별 기본 설정 관리자계정 ID
  |DB명|ID명|비고|
  |---|---|---|
  |MariaDB|root||
  |MySQL|root||
  |PostgreSQL|postgres|postgres-sfs.yaml에서 ENV의 POSTGRES_USER 로 변경가능|
  |MongDB|admin|mongodb-sfs.yaml에서 ENV의 MONGO_INITDB_ROOT_USERNAME 으로 변경가능|
  |Altibase|datacentric|mongodb-sfs.yaml에서 ENV의 USER_ID 로 변경가능|
   
### 3. PVC 생성하기
---
- PVC 생성하기
```bash
$ kubectl apply -f mariadb-pvc.yaml -n test-dev
persistentvolumeclaim/mariadb-pvc created
```
  
- 생성된 PVC 조회
```bash
$ kubectl get pvc mariadb-pvc -n test-dev
NAME           STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS         AGE
mariadb-pvc    Pending                                             100Gi      RWO            local-storageclass   10s
```
  
방금 생성된 PVC를 조회하면 STATUS가 Pending 되어 있는 것을 볼 수 있는데, 아직 PV 가 생성되지 않은 상태입니다.
PV의 생성 시점은 Pod가 PVC 에게 Binding 요청을 하는 시점이며, local-storageclass가 POD와 같은 위치에 PV를 생성하고 Binding을 수행됩니다.
  
### 4. StatefulSet과 Service 생성하기
---
StatefulSet으로 항상 같은 노드에 Pod가 기동되도록 구성하였으며, 외부에서 데이터베이스에 접근할 수 있도록 LoadBalancer 유형으로 서비스를 생성하였습니다.
내부에 지정된 IP Pool에 의해서 랜덤하게 IP가 할당되므로 Service 가 생성된 이후 조회 명령어를 통하여 IP 를 확인할 필요가 있습니다. (Service에서 ExternalIP 항목을 통하여 원하는 IP를 직접 할당하는 것도 가능합니다. 아래 '지정된 IP로 생성하기' 설정 참고)
  
- StatefulSet과 Service 생성하기
```bash
$ kubectl apply -f mariadb-sfs.yaml -n test-dev
statefulset.apps/mariadb-sfs created
service/mariadb-service created
```
  
- 생성된 Pod 조회하기
```bash
$ kubectl get pod -n test-dev
NAME             READY   STATUS    RESTARTS   AGE
mariadb-sfs-0    1/1     Running   0          1m
```

- PVC 바인딩 확인
```bash
$ kubectl get pvc -n test-dev
NAME           STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS         AGE
mariadb-pvc    Bound    pvc-938637b1-b15c-471a-8c85-52fc04e07420   100Gi      RWO            local-storageclass   1m
```
  
- 생성된 Service 및 IP 조회하기
```bash
$ kubectl get svc -n test-dev
NAME               TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)           AGE
mariadb-service    LoadBalancer   10.97.167.180   172.17.250.102   3306:32353/TCP    1m
```
**EXTERNAL-IP** 항목이 외부에서 접근가능한 IP입니다. Port는 각 DB의 기본 포트번호를 사용하도록 설정하였습니다.

- DB별 기본 서비스포트
  |DB명|포트번호|
  |---|---|
  |MariaDB|3306|
  |MySQL|3306|
  |PostgreSQL|5432|
  |MongDB|27017|
  |Altibase|20300|
  
### (참고) 지정된 IP로 생성하기
---
현재 LoadBalancer에 IP Pool로 설정된 172.17.250.100~172.17.250.150 에서 설정 가능하며, 현재 사용하지 않는 IP 대역을 확인할 필요가 있습니다.
  
- 사용하지 않는 IP 확인
```bash
$ kubectl get svc -A | grep LoadBalancer
default             ingress-nginx-controller             LoadBalancer   10.103.70.58     172.17.250.100   80:31710/TCP,443:31407/TCP                                    16d
test-dev            mariadb-service                      LoadBalancer   10.97.167.180    172.17.250.102   3306:32353/TCP                                                5h5m
test-dev            mongodb-service                      LoadBalancer   10.102.164.63    172.17.250.103   27017:30787/TCP                                               4h41m
test-dev            mysql-service                        LoadBalancer   10.106.75.208    172.17.250.101   3306:31567/TCP                                                5h5m
test-dev            postgres-service                     LoadBalancer   10.109.50.6      172.17.250.104   5432:31242/TCP                                                4h9m
```
  
위 명령어를 통하여 172.17.250.X 대역에서 사용하지 않는 IP를 확인하고 아래파일을 수정합니다.
가장 아래 externalIPs를 주석해제하고 원하는 IP를 설정하면 됩니다.
  
```yaml
# mariadb-sfs.yaml 파일 
apiVersion: v1
kind: Service
metadata:
  name: mariadb-service 
  namespace: test-dev
spec:
  selector:
    app: mariadb 
  type: LoadBalancer 
  ports:
  - name: service-port
    port: 3306 
    protocol: TCP
  externalIPs: # 필요한 경우 아이피 지정 가능 (단, 로드밸런서의 아이피 설정 범위(172.17.250.100~172.17.250.150)에 한하여)
    - 172.17.250.120 
```

## 데이터베이스 삭제
배포된 서비스를 삭제하기 위해서는 StatefulSet를 먼저 삭제하고 PVC 를 삭제하면 됩니다. PVC 를 삭제할 경우 모든 데이터가 삭제되니 데이터를 유지할 필요가 있을경우 반드시 먼저 백업을 진행한 후 수행 바랍니다.

```bash
$ kubectl delete -f mariadb-sfs.yaml -n test-dev
statefulset.apps "mariadb-sfs" deleted
service "mariadb-service" deleted

$ kubectl delete -f mariadb-pvc.yaml -n test-dev
persistentvolumeclaim "mariadb-pvc" deleted

$ kubectl delete ns test-dev
namespace "test-dev" deteled
```

## 설치 과정에서 발생하는 오류에 대한 해결 방안

- 재설치 시 관리자 계정의 패스워드가 틀렸다고 나오는 경우
PV도 같이 삭제하거나 이전 설치할 때 사용한 패스워드를 입력하세요. 
Pod 가장 처음 설치할 때만 비밀번호를 세팅하고 이후에는 PV에 저장된 계정정보를 사용하므로 이전에 설치한 PV 를 재활용하는 것이라면 반드시 삭제 후 재설치를 진행하면 됩니다.

- PVC 삭제시 Terminating 상태에서 진행이 되지 않는 경우
```bash
$ k get pvc -n test-dev
NAME             STATUS        VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS         AGE
altibase-pvc     Terminating   pvc-9e46f125-cf38-40dd-816e-97baf0fd7aa8   100Gi      RWO            local-storageclass   33m
```

연동되어있는 StatefulSet을 먼저 삭제해주세요.
만약 실수로 PVC가 삭제되면 현재 실행 중인 서비스(Pod)에 문제가 발생하므로 쿠버네티스에서는 실행 중인 Pod 들을 먼저 삭제하도록 되어있습니다.