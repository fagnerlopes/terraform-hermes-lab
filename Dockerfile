FROM hashicorp/terraform:1.14
WORKDIR /workspace
# Files are bind-mounted by docker-compose; nothing is baked into the image.
