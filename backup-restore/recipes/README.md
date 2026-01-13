## IBM Fusion Backup and Restore Recipe

Data protection is a necessity for enterprise applications. The IBM Fusion Recipe framework enables end users to safeguard their applications by creating [custom backup and restore workflows](https://www.ibm.com/docs/en/fusion-software/2.12.0?topic=restore-custom-backup-workflows). Sample application recipes are provided [here](https://github.com/IBM/storage-fusion/tree/master/backup-restore/recipes), and new recipes can be created by grouping and sequencing resources in the correct order. Additionally, hooks can be utilized to run custom operations between these sequences, supporting application consistency. The recent inclusion of [dynamic recipe](https://www.ibm.com/docs/en/fusion-software/2.12.0?topic=recipe-dynamic) capability, [resource transformations](https://www.ibm.com/docs/en/fusion-software/2.12.0?topic=workflows-resource-transformation) during recovery and [parallel hook execution](https://www.ibm.com/docs/en/fusion-software/2.12.0?topic=recipe-dynamic#sf_dynamic_recipe__section_xz5_gw3_bgc) has made the framework even more robust. 

To help identify application resources that need to be considered for backup and recovery workflows, the kubectl [get-resources](https://github.com/Sandeep-Prajapati/kubectl-get-resources) plugin can be utilized. More details on its usefulness and usage can be found in the [article](https://community.ibm.com/community/user/blogs/sandeep-prajapati/2026/01/11/making-kubernetes-or-openshift-backup-and-restore). Additional articles listed below can help you develop your own Fusion backup and restore recipes.

It is important to note that there is another tool with a similar name, [getResources.sh](https://github.com/IBM/storage-fusion/blob/master/backup-restore/recipes/Fusion-recipe-tools/getResources.sh), which helps retrieve resources that were backed up or restored as part of a given backup or restore workflow, respectively.


## Blogs
There are several resources available to help you better understand the challenges of backup and recovery in an OpenShift environment, and how IBM Fusion Backup & Restore can help address these challenges.

[How IBM Storage Fusion Simplifies Backup and Recovery of Complex OpenShift Applications - Part 1 "So Why is this Complex?"](https://community.ibm.com/community/user/storage/blogs/jim-smith/2023/07/27/ibm-storage-fusion-backup-restore-recipe-1?CommunityKey=e596ba82-cd57-4fae-8042-163e59279ff3)

[How IBM Storage Fusion Simplifies Backup and Recovery of Complex OpenShift Applications - Part 2 "Orchestrations and Recipes"](https://community.ibm.com/community/user/storage/blogs/jim-smith/2023/08/01/how-ibm-storage-fusion-simplifies-backup-and-recov?CommunityKey=e596ba82-cd57-4fae-8042-163e59279ff3)

[How IBM Storage Fusion Simplifies Backup and Recovery of Complex OpenShift Applications - Part 3 “A Deeper Dive into Recipes"](https://community.ibm.com/community/user/storage/blogs/jim-smith/2023/08/04/how-ibm-storage-fusion-simplifies-backup-and-recov?CommunityKey=e596ba82-cd57-4fae-8042-163e59279ff3)

[Fusion Recipe Tips - How to Identify All Resources of an Application](https://community.ibm.com/community/user/blogs/sandeep-prajapati/2024/01/21/identify-application-resources-for-backup-and-reco?CommunityKey=e596ba82-cd57-4fae-8042-163e59279ff3)

[Fusion Recipe Tips - Specify resources for backup and restore workflows](https://community.ibm.com/community/user/blogs/sandeep-prajapati/2024/02/14/fusion-recipe-tips-specify-resources-for-backup-an?CommunityKey=e596ba82-cd57-4fae-8042-163e59279ff3)

[Fusion Recipe Tips - Using hooks](https://community.ibm.com/community/user/blogs/sandeep-prajapati/2024/02/22/fusion-recipe-tips-using-hooks?CommunityKey=e596ba82-cd57-4fae-8042-163e59279ff3)

[Fusion Recipe Tips - Writing Your First Recipe](https://community.ibm.com/community/user/blogs/jim-smith/2024/02/28/fusion-recipe-tips-first-recipe)

[Fusion Recipe Tips - Keeping Database Credentials a Secret](https://community.ibm.com/community/user/blogs/ashish-gupta/2024/03/05/fusion-recipe-tips-keeping-database-credentials-a?CommunityKey=e596ba82-cd57-4fae-8042-163e59279ff3)

[Fusion Recipe Tips - I Didn’t Use a Recipe on Backup and My Application Won’t recover - What Can I Do?](https://community.ibm.com/community/user/blogs/jim-smith/2024/03/13/fusion-recipe-tips-no-backup-recipe?CommunityKey=e596ba82-cd57-4fae-8042-163e59279ff3)

[Fusion Recipe Tips - Running K8 or OpenShift commands during data protection workflows](https://community.ibm.com/community/user/blogs/sandeep-prajapati/2024/03/23/fusion-recipe-tips-running-k8-or-openshift-command?CommunityKey=e596ba82-cd57-4fae-8042-163e59279ff3)

[Fusion Recipe Tips - How Can I Make My Recipe More Globally Applicable](https://community.ibm.com/community/user/blogs/ashish-gupta/2024/03/25/fusion-recipe-tips-keeping-database-credentials-a?CommunityKey=e596ba82-cd57-4fae-8042-163e59279ff3)

[Fusion Recipe Tips - How to undo an operation in case of a failure in the Recipe workflow](https://community.ibm.com/community/user/blogs/sandeep-prajapati/2024/04/05/fusion-recipe-tips-how-to-undo-an-operation-in-cas?CommunityKey=e596ba82-cd57-4fae-8042-163e59279ff3)

[Fusion Recipe Tips - Protecting cluster-scoped resources](https://community.ibm.com/community/user/blogs/jim-smith/2024/04/12/fusion-recipe-tips?CommunityKey=e596ba82-cd57-4fae-8042-163e59279ff3)

[Fusion Recipe Tips - How can I protect the OpenShift image registry using Fusion Recip](https://community.ibm.com/community/user/blogs/ashish-gupta/2024/04/17/fusion-recipe-tips-keeping-database-credentials-a?CommunityKey=e596ba82-cd57-4fae-8042-163e59279ff3)

[Fusion Recipe Tips: Dynamic Recipe](https://community.ibm.com/community/user/blogs/ashish-gupta/2025/06/04/fusion-dynamic-recipe)

[How to make use of Fusion Job hooks?](https://community.ibm.com/community/user/blogs/sandeep-prajapati/2025/06/12/how-to-make-use-of-fusion-job-hooks)

[Using Fusion Label and Annotation Hooks](https://community.ibm.com/community/user/blogs/sandeep-prajapati/2025/06/12/using-fusion-label-and-annotation-hooks)

[How to write Fusion Recipe Check Hook?](https://community.ibm.com/community/user/blogs/sandeep-prajapati/2025/06/12/how-to-write-fusion-recipe-check-hook-condition-st)

[Resources Transformation - Fusion Backup & Restore](https://community.ibm.com/community/user/blogs/ashish-gupta/2025/08/12/resources-transformation-fusion)

[Fusion Recipe: Parallel workflow execution](https://community.ibm.com/community/user/blogs/sandeep-prajapati/2025/09/05/fusion-recipe-parallel-workflow-execution)

[Fusion Backup and Restore considerations for Applications with Webhooks](https://community.ibm.com/community/user/blogs/sandeep-prajapati/2025/11/27/fusion-backup-and-restore-considerations-for-appli)

[Making Kubernetes or OpenShift Backup and Restore Reliable with Resource Discovery](https://community.ibm.com/community/user/blogs/sandeep-prajapati/2026/01/11/making-kubernetes-or-openshift-backup-and-restore)
