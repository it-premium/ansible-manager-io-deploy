staging:
	pipenv run -- ansible-playbook -i inventories/qa/hosts.ini app.yml

production:
	pipenv run -- ansible-playbook -i inventories/prod/hosts.ini app.yml
