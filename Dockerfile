ARG DOCKERHUB_MIRROR=docker.1ms.run
ARG GHCR_MIRROR=ghcr.1ms.run
ARG NPM_REGISTRY=https://registry.npmmirror.com

FROM --platform=$BUILDPLATFORM ${DOCKERHUB_MIRROR}/library/node:20 AS web-builder
WORKDIR /web_ui
ARG NPM_REGISTRY
COPY web_ui/package.json web_ui/yarn.lock ./
RUN corepack enable \
    && REGISTRY_URL="${NPM_REGISTRY%/}/" \
    && sed -i "s#https://registry.npmjs.org/#${REGISTRY_URL}#g; s#https://registry.yarnpkg.com/#${REGISTRY_URL}#g" yarn.lock \
    && yarn config set registry "${NPM_REGISTRY}" \
    && yarn install --frozen-lockfile
COPY web_ui/ ./
RUN yarn build

FROM --platform=$BUILDPLATFORM ${GHCR_MIRROR}/rachelos/base-full:latest AS runtime
ENV PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple

WORKDIR /app
COPY requirements.txt ./requirements.txt
RUN echo "1.0.$(date +%Y%m%d.%H%M)" >> docker_version.txt

ADD ./config.example.yaml ./config.yaml
ADD . .
RUN rm -rf ./static/assets
COPY --from=web-builder /web_ui/dist/index.html ./static/index.html
COPY --from=web-builder /web_ui/dist/assets ./static/assets
RUN chmod +x install.sh \
    && chmod +x start.sh

EXPOSE 8001
CMD ["/app/start.sh"]
