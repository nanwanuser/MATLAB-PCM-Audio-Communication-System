# MATLAB PCM Audio Communication System

[![MATLAB](https://img.shields.io/badge/MATLAB-R2024b-orange.svg)](https://www.mathworks.com/products/matlab.html)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![App Designer](https://img.shields.io/badge/GUI-App%20Designer-blue.svg)](https://www.mathworks.com/products/matlab/app-designer.html)


基于MATLAB的PCM音频编码传输系统，用于数字音频通信的仿真和性能分析。

## 功能特性

- **双声道PCM编码**：左声道8位A律编码，右声道11位均匀量化
- **传输仿真**：TTL电平传输 + AWGN噪声信道
- **性能分析**：误码率曲线、眼图分析、信号对比
- **图形界面**：App Designer专业GUI界面

## 使用方法

1. 在MATLAB中运行 `PCM_App` 启动图形界面
2. 或运行 `main.m` 执行脚本版本
3. 导入音频文件（支持WAV、FLAC、MP3、M4A）
4. 点击"开始处理"进行PCM编码传输仿真
5. 使用分析按钮查看结果

## 系统要求

- MATLAB R2020b+
- Signal Processing Toolbox
- Communications Toolbox

## 主要文件

- `PCM_App.m` - App Designer主程序
- `main.m` - 主处理脚本
- `Rate_SNRcurve.m` - 误码率、眼图分析脚本

## 测试结果

- 支持信噪比范围：-6dB到19dB
- 在12dB以上误码率低于10^-3
- A律编码抗噪性能优于均匀量化

## 作者

Nanwan  
邮箱：nanwan2004@126.com

## 许可证

MIT License