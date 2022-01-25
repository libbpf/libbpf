# IBM Z self-hosted builder

libbpf CI uses an IBM-provided z15 self-hosted builder. There are no IBM Z
builds of GitHub Actions runner, and stable qemu-user has problems with .NET
apps, so the builder runs the x86_64 runner version with qemu-user built from
the master branch.

## Configuring the builder.

### Install prerequisites.

```
$ sudo dnf install docker        # RHEL
$ sudo apt install -y docker.io  # Ubuntu
```

### Add services.

```
$ sudo cp *.service /etc/systemd/system/
$ sudo systemctl daemon-reload
```

### Create a config file.

```
$ sudo tee /etc/actions-runner-libbpf
repo=<owner>/<name>
access_token=<ghp_***>
```

Access token should have the repo scope, consult
https://docs.github.com/en/rest/reference/actions#create-a-registration-token-for-a-repository
for details.

### Autostart the x86_64 emulation support.

```
$ sudo systemctl enable --now qemu-user-static
```

### Autostart the runner.

```
$ sudo systemctl enable --now actions-runner-libbpf
```

## Rebuilding the image

In order to update the `iiilinuxibmcom/actions-runner-libbpf` image, e.g. to
get the latest OS security fixes, use the following commands:

```
$ sudo docker build \
      --pull \
      -f actions-runner-libbpf.Dockerfile \
      -t iiilinuxibmcom/actions-runner-libbpf \
      .
$ sudo systemctl restart actions-runner-libbpf
```

## Removing persistent data

The `actions-runner-libbpf` service stores various temporary data, such as
runner registration information, work directories and logs, in the
`actions-runner-libbpf` volume. In order to remove it and start from scratch,
e.g. when upgrading the runner or switching it to a different repository, use
the following commands:

```
$ sudo systemctl stop actions-runner-libbpf
$ sudo docker rm -f actions-runner-libbpf
$ sudo docker volume rm actions-runner-libbpf
```
