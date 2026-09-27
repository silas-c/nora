# Nora's local action demo

Terraform creates a Docker container serving the sample pages used to check
Nora's native typing, clicking, keyboard, scrolling, and navigation. The same
demo can be recreated for judging without displaying accounts or personal files.
It binds only to localhost, needs no API keys, and does not mount host files.
Nora itself still runs natively on macOS; this container is its demo target.

Install [Terraform](https://developer.hashicorp.com/terraform/install) and start
Docker Desktop or Colima. With Colima, point the provider at its Docker socket:

```sh
# Optional isolated Colima profile, without changing your active Docker context:
colima start nora --activate=false --cpus 2 --memory 2 --disk 10 --mount none --ssh-agent=false --ssh-config=false
export DOCKER_HOST="$(docker context inspect colima-nora --format '{{.Endpoints.docker.Host}}')"

terraform -chdir=infra/demo init
terraform -chdir=infra/demo validate
terraform -chdir=infra/demo plan -out=demo.tfplan
terraform -chdir=infra/demo apply demo.tfplan
```

Open the printed URL in a browser. Ask Nora to type `Hello Nora` in **Test input**,
click **Show typed value**, then click **Next page**. The page should first show
`Typed: Hello Nora`, then `Navigation worked.` All values are sample data;
refreshing the page resets them. `/scroll.html` reports the current scroll offset.

Check the real HTTP endpoint and repeatability:

```sh
curl --fail http://127.0.0.1:8787/
curl --fail http://127.0.0.1:8787/next.html
terraform -chdir=infra/demo plan -detailed-exitcode
# Exit 0 means the deployed demo matches the configuration.
```

When finished, `terraform -chdir=infra/demo destroy` removes the demo container;
`colima stop nora` stops the optional dedicated VM. Keep the generated lock file
in Git, but never commit Terraform state or saved plans.
