-- latency.lua
local latencies = {}
local total_latency = 0
local max_latency = 0
local requests = 0

-- 测试结束时调用
function done(summary, latency, requests)
  print(latency.mean,latency:percentile(50),latency:percentile(75),latency:percentile(90),latency:percentile(99),latency.max,summary.requests/20,summary.bytes/20)
end

