///|
pub struct Client {
  config : @config.Config
  transport : &@transport.Transport
}

///|
/// 传输层是注入的（与 moon-s3／moon-kodo／moon-oss 同一套端口）：业务侧可以换成带连接池、
/// 带自定义超时的实现，测试侧可以塞假端点。
pub fn Client::new(
  config : @config.Config,
  transport : &@transport.Transport,
) -> Client {
  Client::{ config, transport, }
}
