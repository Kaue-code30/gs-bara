# Imagem versionada e atualizada para evitar vulnerabilidades corrigiveis da imagem base.
FROM nginxinc/nginx-unprivileged:1.30.6-alpine3.24

USER root
RUN apk upgrade --no-cache
USER 101

# Nginx nao-root (UID 101) escuta na porta 8080.
# Com readOnlyRootFilesystem no Kubernetes, /tmp recebe um emptyDir.
COPY html/ /usr/share/nginx/html/
EXPOSE 8080
