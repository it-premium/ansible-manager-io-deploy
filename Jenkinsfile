pipeline {
    agent any

    environment {
       ANSIBLE_HOST_KEY_CHECKING='False'
    }

    stages{
        stage('Deploy Manager') {
            steps{
                ansiblePlaybook credentialsId: 'jenkins-ssh-core', inventory: "hosts.ini", playbook: 'app.yml'
            }
        }
    }
}
