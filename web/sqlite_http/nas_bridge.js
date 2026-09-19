// NAS 只读库 JS 桥。
//
// Dart (dart:js_interop) ↔ 本桥 ↔ createDbWorker (Comlink) ↔ sqlite.worker.js。
// 之所以隔一层：Comlink 返回的是 Proxy 对象，从 dart2js 直接触碰 Proxy
// 会触发 "Cannot convert object to primitive value" 一类的隐式转换错误。
// 本桥在 JS 侧把查询结果 JSON.stringify 成纯字符串再交给 Dart，Dart 侧
// jsonDecode 解析，双方只见纯数据。
(function () {
  'use strict';
  var bridge = {
    _w: null,
    init: function (configs, workerUrl, wasmUrl, maxBytes) {
      var self = this;
      return window.createDbWorker(configs, workerUrl, wasmUrl, maxBytes)
        .then(function (w) { self._w = w; return true; });
    },
    // 返回 JSON 字符串: [{columns: [...], values: [[...], ...]}]
    exec: function (sql, args) {
      var w = this._w;
      if (!w) return Promise.reject(new Error('nas bridge not initialized'));
      return w.db.exec(sql, args || []).then(function (r) {
        return JSON.stringify(r);
      });
    },
    bytesRead: function () {
      if (!this._w) return Promise.resolve(0);
      return Promise.resolve(this._w.worker.bytesRead || 0);
    }
  };
  window.__nasBridge = bridge;
})();
