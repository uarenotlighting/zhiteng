# 知疼后端（zhiteng_server）

小程序 / App / Watch **共用** NestJS 后端。请求协议与微光知识库对齐：统一 `POST` + JSON 信封 + 可选 AES 传输加密。

## 统一请求协议

业务接口全部使用 `POST`。加密前 JSON 信封固定为：

```json
{
  "os": "ios",
  "version": "1.0.0",
  "language": "zh-CN",
  "params": {
    "user_id": "",
    "...业务字段": "..."
  }
}
```

- `params.user_id` 必填字符串：登录前 `""`，登录后填当前用户 ID。**服务端不信任该字段做鉴权**，只认 `Authorization: Bearer <token>`。
- 原 query / path 参数全部放进 `params`（如 `id`、`page`、`ifMatch`）。
- 开发默认明文 JSON；生产强制 AES-128-CBC（`AAA##` + JSON，body 为 `16字符key + Base64`，`Content-Type: text/plain`）。
- 开发联调加密：前后端同时设 `TRANSPORT_ENCRYPTION=true`。

例外：`GET /v1/health`、`/docs` 保持明文，便于探针与 Swagger。

## 本地启动

```bash
cd zhiteng_server
npm install
npm run db:up
npx prisma migrate dev
npm run start:dev
```

- API：`http://127.0.0.1:3000`
- OpenAPI：`http://127.0.0.1:3000/docs`

## 开发登录示例（明文信封）

```bash
curl -s http://127.0.0.1:3000/v1/auth/platform/exchange \
  -H 'content-type: application/json' \
  -d '{
    "os":"ios","version":"1.0.0","language":"zh-CN",
    "params":{"user_id":"","platform":"dev","devUserId":"local-dev-user-1"}
  }'
```

拿到 `accessToken` / `user.id` 后：

```bash
curl -s http://127.0.0.1:3000/v1/account/me \
  -H "authorization: Bearer <accessToken>" \
  -H 'content-type: application/json' \
  -d '{
    "os":"ios","version":"1.0.0","language":"zh-CN",
    "params":{"user_id":"<user.id>"}
  }'
```

## 接口一览（均为 POST）

| 路径 | 说明 |
|------|------|
| `/v1/auth/platform/exchange` | 平台登录换 Token |
| `/v1/auth/refresh` | Refresh 轮换 |
| `/v1/account/me` | 当前用户 |
| `/v1/account/health-data/delete` | 删除健康数据 |
| `/v1/pain-entries/create` | 创建记录 |
| `/v1/pain-entries/list` | 列表 |
| `/v1/pain-entries/detail` | 详情（`params.id`） |
| `/v1/pain-entries/update` | 更新（`params.id` + `ifMatch`） |
| `/v1/pain-entries/timeline-events/create` | 追加时间线 |
| `/v1/pain-entries/complete` | 结束发作 |
| `/v1/focus-areas/list` | 关注区域列表 |
| `/v1/focus-areas/create` | 创建关注区域 |
| `/v1/sync/changes` | 增量同步 |
| `/v1/health` | 健康检查（另有 GET 明文） |

## 设计要点

- 内部 `User` + `PlatformIdentity` + `Subject`（预留代记）
- `revision` + `clientMutationId` + tombstone
- 备注等敏感字段库内编码占位，上线前换 KMS
