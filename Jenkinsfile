pipeline {
    agent any

    environment {
       ANSIBLE_HOST_KEY_CHECKING='False'
    }
    parameters {
        booleanParam(name: 'RESTORE',
                     defaultValue: false,
                     description: 'Restore manager dump')
        string(name: 'BACKUP_DATE', defaultValue: '190130-0935', description: 'Restore manager DB on date') 

    }

    stages{
        stage('Deploy Manager') {
            steps{

                ansiblePlaybook credentialsId: 'jenkins-ssh-core', inventory: "hosts.ini", playbook: 'app.yml'
            }
        }

        stage('Select restore date') {
            steps {
                script {
                    files = s3FindFiles bucket: "manager.it-premium.local", glob: "**", onlyFiles: true
                    file = input message: 'User input required', ok: 'Release!', parameters: [choice(name: 'RELEASE_SCOPE', choices: files.collect{ it.name }, description: 'What is the release scope?')]
                }
            }
        }

        stage('Restore data') {
            when { expression { params.RESTORE }}

            steps{
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', accessKeyVariable: 'AWS_ACCESS_KEY_ID', credentialsId: 'manager-credentials', secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {
                    script{
                        env.AWS_ACCESS_KEY_ID=AWS_ACCESS_KEY_ID
                        env.AWS_SECRET_ACCESS_KEY=AWS_SECRET_ACCESS_KEY
                        
                        ansiblePlaybook credentialsId: 'jenkins-ssh-core', inventory: "hosts.ini", playbook: 'restore.yml', extraVars: "${params.BACKUP_DATE}"
                    }

                }

                
            }
        }
    }
}
