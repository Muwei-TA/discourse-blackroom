FROM node:22-alpine
WORKDIR /app
COPY --chown=node:node gateway.mjs config.mjs ./
USER node
ENV NODE_ENV=production BLACKROOM_GATEWAY_CONFIG=/run/blackroom/gateway.json
EXPOSE 8080
CMD ["node", "gateway.mjs"]
