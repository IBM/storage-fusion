This is a sample recipe which provides a backup and restore workflow for an application that has two data sources to demonstrate how the sequences for the resources and PVCs for each data source are combined in a single recipe. In this example, we are using a Redis and MySQL database instances. Use this recipe as a template for applications with multiple database engine types. 

## How to deploy: 

1. oc new-project combined
2. Clone this project
    ```
    git clone git@github.ibm.com:ProjectAbell/workload-squad.git
    ```
2. cd usecases/mobily 
3. Deploy redis
    ```
    oc apply -f image-based/deploy-redis.yaml
    ```
4. Deploy mysql 3 instances
    ```
    oc apply -f image-based/deploy-mysql.yaml
    oc apply -f image-based/deploy-mysql-1.yaml
    oc apply -f image-based/deploy-mysql-2.yaml
    ```


## Preparation for Fusion Backup & Restore

1. Need to provide the label to few resources for recipe execution. 
    So we provided below script to label the resources.
    ```
    usecases/mobily/update_labels.sh
    ```
2. Run the update_labels.sh to add lables to deployment and related pvc.
   For example , 
   1. To add the label to redis deployment and pod 
    ```
    ./update_labels.sh uat redis fusion-label=redis 
    ```
    2. To add the label to mysql deployment and pod 
    ```
    ./update_labels.sh uat mysql fusion-label=mysql 
    ```
 3. Apply the recipe and take backup.


