#!/bin/bash

set -eo pipefail

# Check two arguments are provided - one for env file and other for command
if [ $# -lt 2 ]; then
  printf "Usage : $0 arg1 arg2\n"
  printf "Options: 
    arg1 = config file 
    arg2 = 1..7.
        1 = Generate terraform.tfvar file.
        2 = Initialize terraform, create workspace and plan.
        3 = Deploy bootstrap resources.
        4 = Update and migrate terraform state to GCS backend.
        5 = Generate github keys and configure git global.
        6 = Clone the private GitHub repo and push into cloud source repo.
        7 = Run terraform to add cloud build CI job triggers for next LZ phase.
        \n"
  exit
fi

# Constant variables to report command execution outcome
STEP_DONE="DONE!\n"
STEP_SUCCESS="SUCCESS!\n"
STEP_FAIL="FAIL!\n"

# Function to return the current time
timestamp()
{
    date +"%Y-%m-%d %T"
    # usage printf "$(timestamp): 0-1: Checking client log file exist ..."
}

printf "\n>>>>>>>>>> RUNNING: STEP 0 - Source config file and check log file.\n\n"
printf "$(timestamp) [0-0]: Sourcing environment variables from .conf file..." 
source $1 # Source config file
printf $STEP_DONE; sleep 2


printf "$(timestamp) [0-1]: Checking client log file exist ..."
if [[ -f $LOG_FILE_PATH ]]; then
    #printf "YES! - ${LOG_FILE_PATH}\n"
    printf "YES!\n"
else
    printf "NO!\n"
    printf "$(timestamp) [0-2]: Creating log file..."
    touch $LOG_FILE_PATH
    printf "${LOG_FILE_PATH} created successfully!\n"
fi; sleep 2

# Function to check file exists and prints outcome
check_file_exists()
{
    local file="$1"
    local number="$2"
    
    if [ -f $file ]; then
        printf $STEP_SUCCESS | tee -a $LOG_FILE_PATH
    else
        printf $STEP_FAIL | tee -a $LOG_FILE_PATH
        printf "$(timestamp) [ERROR]: $file file is missing. Execute step #$number.\n" | tee -a $LOG_FILE_PATH
        exit 1
    fi
}

# Switch statements based on second argument
case $2 in
1) # >>>> STEP 1 - Initialize env variables and generate terraform.tfvar file
    printf "\n>>>>>>>>>> RUNNING: STEP #1 - Intialize terraform variables and generate var file.\n\n" | tee -a $LOG_FILE_PATH
    printf "$(timestamp) [1-1]: Initialising terraform variables..." | tee -a $LOG_FILE_PATH
    if [[ (-z "${CLIENT_SHORT_NAME}") || 
        (-z "${ORG_ID}") || 
        (-z "${ORG_DOMAIN}") ||       
        (-z "${BILL_ID}") || 
        (-z "${GCS_REGION}") || 
        (-z "${DEFAULT_REGION}") ||
        (-z "${WORKLOAD_NETWORK_REGIONS}") 
    ]]
    then
    printf $STEP_FAIL | tee -a $LOG_FILE_PATH
    printf "$(timestamp) [ERROR]: One or more variables not populated. Check config file.\n" | tee -a $LOG_FILE_PATH
    exit 1
    fi
    printf $STEP_SUCCESS | tee -a $LOG_FILE_PATH; sleep 2
    sleep 2

    printf "$(timestamp) [1-2]: Generating terraform.tfvars file..." | tee -a $LOG_FILE_PATH

    cat > ${PWD}/terraform.tfvars <<EOL
    client_short_name = "${CLIENT_SHORT_NAME}"
    org_id = "${ORG_ID}"
    org_domain = "${ORG_DOMAIN}"
    billing_account_id = "${BILL_ID}"
    gcs_region = "${GCS_REGION}"
    default_region = "${DEFAULT_REGION}"
    workload_env_subnet_regions = "${WORKLOAD_NETWORK_REGIONS}" 
EOL

    printf $STEP_SUCCESS | tee -a $LOG_FILE_PATH; sleep 1

    printf "$(timestamp) [1-3]: Review terraform.tfvar contents below before proceeding to next step:\n\n"
    cat ${PWD}/terraform.tfvars
    printf "\n\n"; sleep 1
;;

2) # >>>> STEP 2 - Initialize terraform, create workspace and plan
    printf "\n>>>>>>>>>> RUNNING: STEP #2 - Initialize terraform, create workspace and plan.\n\n" | tee -a $LOG_FILE_PATH
    printf "$(timestamp) [2-1]: Checking terraform.tfvars file exists..." | tee -a $LOG_FILE_PATH

    check_file_exists "${PWD}/terraform.tfvars" "1"

    printf "$(timestamp) [2-2]: Initializing terraform..." | tee -a $LOG_FILE_PATH
    terraform init 2>&1 >> $LOG_FILE_PATH
    printf $STEP_SUCCESS | tee -a $LOG_FILE_PATH; sleep 1

    printf "$(timestamp) [2-3]: Create new terraform workspace 'bootstrap'..." | tee -a $LOG_FILE_PATH
    
    set +e # Skip warning message about existing workspace
    terraform workspace new bootstrap 1>&2 >> $LOG_FILE_PATH
    printf $STEP_SUCCESS | tee -a $LOG_FILE_PATH; sleep 1

    printf "$(timestamp) [2-4]: Format terraform files and validate..." | tee -a $LOG_FILE_PATH
    terraform fmt 2>&1 >> $LOG_FILE_PATH

    set -e # Exit on error
    terraform validate 1>&2 >> $LOG_FILE_PATH
    printf $STEP_SUCCESS | tee -a $LOG_FILE_PATH; sleep 1

    printf "$(timestamp) [2-5]: Generate terraform plan..." | tee -a $LOG_FILE_PATH
    if [ -f "${PWD}/$TF_PLAN" ]
    then
        printf "Found existing plan! Replacing..." | tee -a $LOG_FILE_PATH
        rm $TF_PLAN
    fi
    
    terraform plan -out=$TF_PLAN 2>&1 >> $LOG_FILE_PATH
    #printf $STEP_SUCCESS | tee -a $LOG_FILE_PATH

    printf "\n[INSTRUCTION]: Review the generated plan before deploying by running 'terraform show bootstrap.tfplan'.\n\n"; sleep 2
;;

3) # >>>> STEP 3 - Deploy bootstrap resources
    printf "\n>>>>>>>>>> RUNNING: STEP #3 - Deploy bootstrap resources.\n\n" | tee -a $LOG_FILE_PATH
    printf "$(timestamp) [3-1]: Checking $TF_PLAN exists..." | tee -a $LOG_FILE_PATH

    check_file_exists "${PWD}/$TF_PLAN" "2"

    printf "$(timestamp) [3-2]: Deploying the bootstrap infrastructure..." | tee -a $LOG_FILE_PATH
    set -e # Exit on error
    terraform apply -auto-approve $TF_PLAN  2>&1 >> $LOG_FILE_PATH
    printf $STEP_SUCCESS | tee -a $LOG_FILE_PATH; sleep 1

    printf "$(timestamp) [3-3]: Review terraform output below: \n\n"
    terraform show output; sleep 1
;;

4) # >>>> STEP 4 - Update and migrate terraform state to GCS backend 
    printf "\n>>>>>>>>>> RUNNING: STEP #4 - Update and migrate terraform state to GCS backend.\n\n" | tee -a $LOG_FILE_PATH


    terraform init -migrate-state

;;

5) # >>>> STEP 5 - Generate github keys and configure git global 
    printf "\n>>>>>>>>>> RUNNING: STEP #5 - Generate github keys and configure git global.\n\n" | tee -a $LOG_FILE_PATH

    printf "$(timestamp) [5-1]: Generate keys to connect to private Github repo..." | tee -a $LOG_FILE_PATH
    ssh-keygen -t rsa -b 4096 -N "" -q -C "${GITHUB_BOT_USER}" -f ~/.ssh/id_github # command output is suppressed
    ssh-keyscan -t rsa github.com 2>&1 | tee ~/.ssh/known_hosts 
    cat ssh_config_template > ~/.ssh/config # Check file exists!!!
    printf $STEP_SUCCESS | tee -a $LOG_FILE_PATH; sleep 1

    printf "$(timestamp) [5-2]: Configure the cloudshell git session (email, name and credential)..." | tee -a $LOG_FILE_PATH
    git config --global user.email "${GITHUB_BOT_USER}" && git config --global user.name "${GITHUB_BOT_NAME}" 2>&1 >> $LOG_FILE_PATH
    git config --global credential.https://source.developers.google.com.helper gcloud.sh 2>&1 >> $LOG_FILE_PATH
    printf $STEP_SUCCESS | tee -a $LOG_FILE_PATH; sleep 1

    printf "\n[INSTRUCTION]: 
    Add the public SSH key as a deploy key on the Github repo.
    Copy the generated public key and add it as a deploy key on the private Github repo.
    See instructions here : $DEPLOY_KEY_DOC_LINK
    Once you've added the deploy key to the Github repo, run step #6.\n\n"
    sleep 2
;;

6) # >>>> STEP 6 - Clone the private GitHub repo and push into cloud source repo
    set -e # Toggle to exit on error
    printf "\n>>>>>>>>>> RUNNING: STEP #6 - Clone the private GitHub repo and push into cloud source repo.\n\n" | tee -a $LOG_FILE_PATH
    export GITHUB_SSH_URL=$(echo ${GITHUB_URL} | sed 's/https:\/\/github.com\//git\@github.com:/;s/$/.git/')
    export SEED_PROJ=$(terraform output -raw seed_project_id)
    export GITHUB_REPO_NAME=$(basename ${GITHUB_URL})
    cd ${HOME} 
    git clone ${GITHUB_SSH_URL}
    cd ${HOME}/${GITHUB_REPO_NAME}
    git remote add google https://source.developers.google.com/p/${SEED_PROJ}/r/${GITHUB_REPO_NAME}
    git push --all google
    git checkout --track remotes/origin/develop
    git push google
;;

7) # >>>> STEP 7 - Run terraform to add cloud build CI job triggers for next LZ phase
    set -e # Toggle to exit on error
    printf "\n>>>>>>>>>> RUNNING: STEP #7 - Run terraform to add cloud build CI job triggers for next LZ phase.\n\n" | tee -a $LOG_FILE_PATH
    cd ${WORKDIR}
    terraform apply -auto-approve -var="enable_cb_triggers=true"
;;

esac
