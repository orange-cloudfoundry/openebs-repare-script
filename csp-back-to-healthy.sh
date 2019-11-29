#!/bin/bash
#set -x
kubectl get csp
export state="Offline"
export nb_csp_offline=$(kubectl get csp  |grep $state |wc -l)
echo "nb csp "$state": "$nb_csp_offline
if [ $nb_csp_offline = 2 ]
then
    # check if all 3 pod of  cstor-pool are in running mode
    export nb_pod_cstor_pool=$(kubectl get pod -n openebs  -l app=cstor-pool |grep Running| wc -l)
    if [ $nb_pod_cstor_pool = 3 ]
    then 
        echo "csp "/${state}":"
        echo "============"
        csp_offline=$(kubectl get csp  |grep $state | cut -d ' ' -f1)
        ls_csp_offline=$(echo $csp_offline|sed 's/ /,/g')
        echo ${ls_csp_offline}
        for u in csp_offline;
          do
            kubectl patch csp $u --type=merge --patch '{"status":{"phase":"Healthy"}}';
          done;
        ## create the script for extrating the replica id of pvc impacted by csp
        export jsonpath="'{range .items[*]}{.metadata.name}{\" == \"}{.spec.replicaid}{\"\\\\n\"}'"
        echo "kubectl get cvr -n openebs -l 'cstorpool.openebs.io/name in ("${ls_csp_offline}")'  -o jsonpath=$jsonpath" > pvc_extract.sh
        echo "pvc replica id impacted by csp_offline:"
        echo "======================================="
        sh pvc_extract.sh | cut -d ' ' -f3
        echo "change csp status from Offline to Init:"
        echo "======================================="
        kubectl get csp -o yaml | sed 's/phase: Offline/phase: Init/g' > update_state.yaml
        kubectl replace -f update_state.yaml --force
        echo "wait until all csp have healthy status"
        echo "======================================"
        export nb_csp_healthy="0" ; while [ $nb_csp_healthy !=  3 ]; do kubectl get csp; sleep 3; export nb_csp_healthy=$(kubectl get csp  |grep Healthy |wc -l);  done;
        echo "change consistencyfactor, replicationFactor, ignore replica id:"
        echo "==============================================================="
        kubectl get  cStorVolume  -n openebs -o yaml |sed 's/consistencyFactor: 2/consistencyFactor: 1/g'|sed 's/replicationFactor: 3/replicationFactor: 1/g' > file.yaml
        for u in $(sh pvc_extract.sh | cut -d ' ' -f3); do cat file.yaml|sed 's/'$u'/#'${u}'/g' >tmp.yaml;mv tmp.yaml file.yaml; done
        #       kubectl replace -f file.yaml --force
    else
     echo "pods of ctor pool are not all  in running mode => script not applicable"
fi
else
        echo "script not applicable"
fi
