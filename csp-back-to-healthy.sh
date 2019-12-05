#!/bin/bash
#set -x
state="Offline"
nb_csp_offline=$(kubectl get csp  |grep $state |wc -l)
echo "nb csp group by status:"
echo "======================="

echo "Healthy:" $(kubectl get csp -o=jsonpath='{.items[*].status.phase}' | grep -o Healthy | wc -l)
echo "Init:" $(kubectl get csp -o=jsonpath='{.items[*].status.phase}' | grep -o Init | wc -l)
echo "Offline:" $(kubectl get csp -o=jsonpath='{.items[*].status.phase}' | grep -o Offline | wc -l)
echo "Degraded:" $(kubectl get csp -o=jsonpath='{.items[*].status.phase}' | grep -o Degraded | wc -l)
echo "Recreate:" $(kubectl get csp -o=jsonpath='{.items[*].status.phase}' | grep -o Recreate | wc -l)


echo "nb cvr group by status:"
echo "======================="
echo "Healthy:" "$(kubectl get cvr  -n openebs -o=jsonpath='{.items[*].status.phase}' | grep -o Healthy | wc -l)"
echo "Offline:" $(kubectl get cvr  -n openebs -o=jsonpath='{.items[*].status.phase}' | grep -o OffLine | wc -l)
echo "Degraded:" $(kubectl get cvr  -n openebs -o=jsonpath='{.items[*].status.phase}' | grep -o Degraded | wc -l)
echo "Recreate:" $(kubectl get cvr  -n openebs -o=jsonpath='{.items[*].status.phase}' | grep -o Recreate | wc -l)

echo "cstor pull status:"
echo "======================="
kubectl get pod -n openebs  -l app=cstor-pool

if [ ${nb_csp_offline} = 2 ]
then
    # check if all 3 pod of  cstor-pool are in running mode
    nb_pod_cstor_pool=$(kubectl get pod -n openebs  -l app=cstor-pool |grep Running| wc -l)
    if [ ${nb_pod_cstor_pool}  = 3 ]
    then
        echo "try to repare the case of 2 disks have been changed (ie they are Offline)"
        echo "csp "/${state}":"
        echo "============"
        csp_offline=$(kubectl get csp  |grep $state | cut -d ' ' -f1)
        ls_csp_offline=$(echo ${csp_offline}|sed 's/ /,/g')
        echo ${ls_csp_offline}

        ## create the script for extract the replica id of pvc impacted by csp
        jsonpath="'{range .items[*]}{.metadata.name}{\" == \"}{.spec.replicaid}{\"\\\\n\"}'"
        echo "kubectl get cvr -n openebs -l 'cstorpool.openebs.io/name in ("${ls_csp_offline}")'  -o jsonpath=${jsonpath}" > pvc_extract.sh
        echo "pvc replica id impacted by csp_offline:"
        echo "======================================="
        sh pvc_extract.sh | cut -d ' ' -f3
        echo "change csp status from Offline to Init:"
        echo "======================================="
        for u in ${csp_offline};
          do
            kubectl patch csp $u --type=merge --patch '{"status":{"phase":"Init"}}';
          done;
        echo "now wait until all csp have healthy status"
        echo "======================================"
        nb_csp_healthy="0" ;
        while [[ ${nb_csp_healthy} !=  3 ]];
          do
            kubectl get csp;
            sleep 3;
            nb_csp_healthy=$(kubectl get csp  |grep Healthy |wc -l);
          done;

        echo "change consistencyfactor, replicationFactor, ignore replica id:"
        echo "==============================================================="
        # create the file for the patch
        echo 'spec:' >tmp.yaml
        echo '  consistencyFactor: 1' >>tmp.yaml
        echo '  replicationFactor: 1' >>tmp.yaml
        echo '  replicaDetails:' >> tmp.yaml
        echo '    knownReplicas: ' >> tmp.yaml
        for u in $(sh pvc_extract.sh | cut -d ' ' -f3);
          do
            echo '      '${u}': null' >>tmp.yaml;
          done;
        echo 'status:' >> tmp.yaml
        echo '  replicaDetails:' >> tmp.yaml
        echo '    knownReplicas:' >> tmp.yaml;
        for u in $(sh pvc_extract.sh | cut -d ' ' -f3);
          do
            echo '      '${u}': null' >>tmp.yaml;
          done;
        # end of patch creation


        echo "apply patch on each cStorVolume:"
        echo "================================"
        for cStorVolume in $(kubectl get cStorVolume -n openebs | cut -d ' ' -f1);
        do
            kubectl patch cStorVolume ${cStorVolume} -n openebs --type=merge --patch "$(cat tmp.yaml)";
        done;

    else
     echo "pods of ctor pool are not all  in running mode => script not applicable"
fi
else
        echo "nb csp Offline is not 2/3 => script is not applicable"
fi
