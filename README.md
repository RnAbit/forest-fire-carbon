## 林火碳卫士（本地行政区 GeoJSON 下钻）

本项目的 `platform_K.html` 已改为 **不在运行时调用阿里云行政区 GeoJSON 接口**，下钻时只读取本地静态文件：

- **本地目录约定**：`./geojson/areas_v3/bound/{adcode}_full.json`
- **可选单文件包**：`./geojson.bundle.js`（让 `file://` 直接打开也能下钻）

### 1) 一键预下载省/市 GeoJSON 到本地

在项目根目录打开 PowerShell，运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\prefetch-geojson.ps1
```

下载完成后会生成目录 `geojson/areas_v3/bound/`，其中包含：

- 省级：`110000_full.json`、`320000_full.json` 等
- 地级市（仅非直辖市/港澳台）：从各省 GeoJSON 自动解析并下载

### 2) 生成“单文件地图数据包”（推荐用于比赛离线分发）

如果你希望 **任何环境（包含 `file://` 直接双击打开）** 都能使用地图下钻，不依赖 `fetch`，可以把所有 `*_full.json` 打成一个 `geojson.bundle.js`：

```powershell
python .\tools\build-geojson-bundle.py
```

生成后会得到：

- `geojson.bundle.js`

`platform_K.html` 已经默认用 `<script src="./geojson.bundle.js"></script>` 引入它；存在就走离线内存读取，不存在就自动回退到按需读取 `geojson/` 目录。

### 2) 部署/运行注意

- **必须通过 Web 服务器访问**（部署到任意静态站点即可）。如果直接双击用 `file://` 打开，浏览器可能会拦截 `fetch` 本地文件，导致下钻失败。
- 部署时记得把 `geojson/` 目录一起发布到站点根目录下，保持相对路径不变。

> 如果你使用了 `geojson.bundle.js`，则 `file://` 直接打开也能下钻（因为不需要 `fetch` 读取本地文件）。

