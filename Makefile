staging:
	uv run -- ansible-playbook -i inventories/qa/hosts.ini app.yml

production:
	uv run -- ansible-playbook -i inventories/prod/hosts.ini app.yml

bootstrap:
	uv sync
	uv run -- ansible-galaxy collection install -r requirements.yml
