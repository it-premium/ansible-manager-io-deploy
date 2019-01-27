pipeline {
    agent any

    environment {
       ANSIBLE_HOST_KEY_CHECKING='False'
    }
    parameters {
        booleanParam(name: 'RESTORE',
                     defaultValue: false,
                     description: 'Restore manager dump')
    }

    stages{
        stage('Deploy Manager') {
            steps{

                ansiblePlaybook credentialsId: 'jenkins-ssh-core', inventory: "hosts.ini", playbook: 'app.yml'
            }
        }
        stage('Restore data') {
            when { expression { params.RESTORE }}

            steps{
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', accessKeyVariable: 'AWS_ACCESS_KEY_ID', credentialsId: 'manager-credentials', secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {
                    script{
                        env.AWS_ACCESS_KEY_ID=AWS_ACCESS_KEY_ID
                        env.AWS_SECRET_ACCESS_KEY=AWS_SECRET_ACCESS_KEY
                        
                        ansiblePlaybook credentialsId: 'jenkins-ssh-core', inventory: "hosts.ini", playbook: 'restore.yml'
                    }

                }

                
            }
        }
    }
}
