# Terraform + AWS + EKS + EBS CSI driver (advanced)

This is an advanced Terraform project, demonstrating how to write a Terraform playbook in order to automatically provision an EKS cluster and also enable the ebs csi driver for aws volume creation.
The outstanding feature is to be completely dynamic, meaning you can provide any number of input variables, drivers, and node groups and instances . It benefits from lists, objects, and loops.
To handle EKS vpc creation process, a module named aws-vpc has been created, which could be a good example of module creation in terraform.
- Note that to enable auto-scaling, meaning dynamic increase and decrease in node numbers based on cluster load, we need some more configurations, which will be covered in another project.

## Requirement

Requirement         | Specification
------------------- | ----------------------
OS                  | Ubuntu 22.04
Language            | Terraform


## How to use
- Make sure that you have already installed terraform on you machine.
- Make sure that you have configured aws credentials on you machine, and you can connect to your account.
- Clone this project 
- `variables.tf` also includes default values for variables, but you can create a `.tfvars` file and specify your desired values for variables.
- then simply run:

```bash
terraform init
terraform apply -auto-approve
```
- By default, it will create an EKS `v1.28` cluster in `eu-central` region including two availability zones ("eu-central-1a","eu-central-1b") and each zone having a public and a private subnet, and dedicated nats plus a shared internet gateway .
- Cluster is configured to have a node group of type `"t3.medium` VMs running 2 vms as desire. (min=1, max=3)
- Refer to the variables.tf file to see all configurations. Add a `.tfvars` file if you prefer to change each variable value.

## How project works
- `aws-vpc-module` is responsible to create a vpc with the following design. It creates many resources like vpc, subnet, gateway, nat, elastic ip, security group and so on:

![img.png](cluster-architecture.png)

- `main.tf` in the main folder calls the `aws-vpc-module` to create the required vpc resources and then creates cluster, node-group, and enables drivers. To do so, it takes the help of `iam-role-and-policies.tf` file to create required iam roles and policies.
- This project take the advantage of many terraform details and tips, please Refer to `main.tf` and `variables.tf` files to learn more about them. 