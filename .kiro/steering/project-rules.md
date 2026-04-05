## 注意事项

1. 不生成 markdown 相关文档
2. 增加日志时需要同步更新双语言
3. 不需要保留兼容接口

## 命名规范

类 / 结构体 / 枚举 / 协议：PascalCase（大驼峰）
枚举 case：lowerCamelCase
变量 & 常量（普通）：lowerCamelCase
变量 & 常量（Bool）：必须体现「是 / 能 / 有」
规则：is / has / can / should 开头
变量 & 常量（集合）：使用复数形式
函数 / 方法：lowerCamelCase，读起来像一句话
函数命名（避免）：get / set
函数参数（第一个）：通常不加参数标签
无副作用方法：返回新值，使用描述性动词或形容词
有副作用方法：使用明确动词
SwiftUI View：PascalCase + View / Screen / Page（团队统一）
ViewModel：PascalCase + ViewModel
@State / @Binding：lowerCamelCase，多用于状态语义
Closure / 回调：语义化命名
Error 类型：PascalCase + Error
本地化 Key：统一命名空间，避免裸字符串
本地化方法命名：避免单字母
