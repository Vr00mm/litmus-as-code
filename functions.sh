function decode_base64_url() {
  local len=$((${#1} % 4))
  local result="$1"
  if [ $len -eq 2 ]; then result="$1"'=='
  elif [ $len -eq 3 ]; then result="$1"'='
  fi
  echo "$result" | tr '_-' '/+' | openssl enc -d -base64
}

function decode_jwt(){
   decode_base64_url $(echo -n $2 | cut -d "." -f $1) | jq .
}

function login()
{
      STATUS=$(curl -vvvv -s -o /dev/null -w '%{http_code}' -XGET ${LITMUS_URL} 2>/dev/null)
      if [ $STATUS -ne 200 ] ; then
        echo "Smoke test failed litmus unreachable !"
        exit 1;
      fi

    response=`curl --silent -X POST --header "Content-Type=application/json" -d "{\"username\": \"${LITMUS_USERNAME}\", \"password\": \"${LITMUS_PASSWORD}\"}" "${LITMUS_URL}/auth/login" 2>/dev/null`
    export TOKEN=`echo ${response} |jq -r '.access_token // "null"'`
    if [ "${TOKEN}" == "null" ]; then
	echo "Une erreur est survenue."
        exit 1
    fi
}

function graphql_request()
{
	REQUEST="${1}"
        curl --silent \
        -X POST \
        --header "User-Agent: Go-http-client/1.1" \
        --header "Content-Type: application/json" \
        --header "Authorization: ${TOKEN}" \
        -d "${REQUEST}" \
        "${LITMUS_URL}/api/query" 2>/dev/null
}


function create_user()
{
	USER_UID=`get_user_uid`
	graphql_request "{\"operationName\":\"CreateUser\",\"variables\":{\"user\":{\"username\":\"${LITMUS_USERNAME}\",\"email\":\"\",\"name\":\"\",\"role\":\"admin\",\"userID\":\"${USER_UID}\"}},\"query\":\"mutation CreateUser(\$user: CreateUserInput! ) {\\n  createUser(user: \$user) {\\n    username\\n    created_at\\n    updated_at\\n    deactivated_at\\n    __typename\\n  }\\n}\\n\"}" >/dev/null
        login

}

function get_user_uid()
{
	decode_jwt 2 "$TOKEN" | jq -r '.uid'
}
function get_project_id()
{
    PROJECT_NAME="${1}"
    get_projects | jq -r ".data.listProjects | .[] | select(.name==\"${PROJECT_NAME}\").id"
}

function get_projects()
{
	graphql_request '{"query":"query{listProjects{id name created_at}}"}'
}

function create_project()
{
    PROJECT_NAME="${1}"
    graphql_request "{\"operationName\":\"createProject\",\"variables\":{\"projectName\":\"${PROJECT_NAME}\"},\"query\":\"mutation createProject(\$projectName: String! ) {\\n  createProject(projectName: \$projectName) {\\n    members {\\n      user_id\\n      role\\n      user_name\\n      invitation\\n      joined_at\\n      __typename\\n    }\\n    name\\n    id\\n    __typename\\n  }\\n}\\n\"}" >/dev/null
}

function add_gitops()
{
    PROJECT_NAME="${1}"
    PROJECT_ID=`get_project_id "${PROJECT_NAME}"`
    GITOPS_URL="${2}"
    GITOPS_BRANCH="${3}"
    GITOPS_SSH_KEY="${4}"
    graphql_request "{\"operationName\":\"enableGitOps\",\"variables\":{\"gitConfig\":{\"ProjectID\":\"${PROJECT_ID}\",\"RepoURL\":\"${GITOPS_URL}\",\"Branch\":\"${GITOPS_BRANCH}\",\"AuthType\":\"ssh\",\"Token\":\"\",\"UserName\":\"user\",\"Password\":\"user\",\"SSHPrivateKey\":\"${GITOPS_SSH_KEY}\"}},\"query\":\"mutation enableGitOps(\$gitConfig: GitConfig! ) {\n  enableGitOps(config: \$gitConfig)\n}\n\"}" >/dev/null
}

function add_hub()
{
    PROJECT_NAME="${1}"
    PROJECT_ID=`get_project_id "${PROJECT_NAME}"`
    HUB_NAME="${2}"
    HUB_URL="${3}"
    HUB_BRANCH="${4}"
    graphql_request "{\"operationName\":\"addMyHub\",\"variables\": {\"MyHubDetails\": {\"HubName\": \"${HUB_NAME}\", \"RepoURL\": \"${HUB_URL}\", \"RepoBranch\": \"${HUB_BRANCH}\", \"IsPrivate\":false,\"AuthType\":\"basic\",\"Token\":\"\",\"UserName\":\"user\",\"Password\":\"user\",\"SSHPrivateKey\":\"\",\"SSHPublicKey\":\"\"},\"projectID\":\"${PROJECT_ID}\"},\"query\":\"mutation addMyHub(\$MyHubDetails: CreateMyHub!, \$projectID: String! ) {\\n  addMyHub(myhubInput: \$MyHubDetails, projectID: \$projectID) {\\n    HubName\\n    RepoURL\\n    RepoBranch\\n    __typename\\n  }\\n}\\n\"}"
}

function get_hubs()
{
    PROJECT_ID="${1}"
    graphql_request "{\"operationName\":\"getHubStatus\",\"variables\":{\"data\":\"${PROJECT_ID}\"},\"query\":\"query getHubStatus(\$data: String! ) {\\n  getHubStatus(projectID: \$data) {\\n    id\\n    HubName\\n    RepoBranch\\n    RepoURL\\n    TotalExp\\n    IsAvailable\\n    AuthType\\n    IsPrivate\\n    Token\\n    UserName\\n    Password\\n    SSHPrivateKey\\n    SSHPublicKey\\n    LastSyncedAt\\n    __typename\\n  }\\n}\\n\"}"
}

function delete_hub()
{
    HUB_ID="${1}"
    graphql_request "{\"operationName\":\"deleteMyHub\",\"variables\":{\"hub_id\":\"${HUB_ID}\"},\"query\":\"mutation deleteMyHub(\$hub_id: String! ) {\\n  deleteMyHub(hub_id: \$hub_id)\\n}\\n\"}"
}

function clear_hubs()
{
    PROJECT_NAME="${1}"
    PROJECT_ID=`get_project_id "${PROJECT_NAME}"`

    hubs=`get_hubs ${PROJECT_ID}`
    for rowHubs in $(echo "${hubs}" | jq -r '.data.getHubStatus | .[] | @base64'); do
        _jqHubs() {
            echo ${rowHubs} | base64 --decode | jq -r ${1}
        }
        delete_hub $(_jqHubs '.id')

    done
}

function create_or_update_projects()
{
    manifest=`cat ${LITMUS_CONFIGURATION_PATH}`
    for row in $(echo "${manifest}" | jq -r ".[] | select(.name==\"${KUBE_CONTEXT}\").projects[] | @base64"); do
        _jq() {
            echo ${row} | base64 --decode | jq -r ${1}
        }
        create_project "$(_jq '.name')" >/dev/null
	clear_hubs "$(_jq '.name')"
        GITOPS_URL=`echo ${manifest} | jq -r ".[] | select(.name==\"${KUBE_CONTEXT}\") | .gitops.GITOPS_URL"`
        GITOPS_BRANCH=`echo ${manifest} | jq -r ".[] | select(.name==\"${KUBE_CONTEXT}\") | .gitops.GITOPS_BRANCH"`
        GITOPS_SSH_KEY=`echo ${manifest} | jq -r ".[] | select(.name==\"${KUBE_CONTEXT}\") | .gitops.GITOPS_SSH_KEY"`

        for row2 in $(_jq '.hubs' | jq -r '.[] | @base64'); do
            _jq-sub() {
                echo ${row2} | base64 --decode | jq -r ${1}
            }
            add_hub "$(_jq '.name')" "$(_jq-sub '.name')" "$(_jq-sub '.url')" "$(_jq-sub '.branch')" > /dev/null
        done
        add_gitops "$(_jq '.name')" "${GITOPS_URL}" "${GITOPS_BRANCH}" "${GITOPS_SSH_KEY}"
    done
}

function deploy_agents()
{
    PROJECT_ID=`get_projects |jq -r '.data.listProjects[0].id'`
    manifest=`cat ${LITMUS_CONFIGURATION_PATH}`
    for row in $(echo "${manifest}" | jq -r ".[] | select(.name==\"${KUBE_CONTEXT}\").agents[] | @base64"); do
        TARGET=`echo $row | base64 --decode`
        echo -n > $HOME/.litmusconfig
        litmusctl config set-account --endpoint "${LITMUS_URL}" --password="${LITMUS_PASSWORD}" --username="${LITMUS_USERNAME}"
        kubectl config use-context ${TARGET} >/dev/null
        agentExist=`litmusctl get agents --project-id="${PROJECT_ID}" -ojson |jq -r ".getCluster[] | select(.cluster_name==\"agent-${TARGET}\") // \"\""`
        if [ -z $agentExist ]
        then
          litmusctl --kubeconfig "${KUBECONFIG}" create agent --namespace litmus --project-id="${PROJECT_ID}" --agent-name="agent-${TARGET}" --non-interactive
        fi
    done
}
