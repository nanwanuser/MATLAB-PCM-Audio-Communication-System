clear;
close all;
clc;

%% 采样设置
% 先获取音频文件的真实采样率
audio_file = '华晨宇 _ 宿涵 - 烟火里的尘埃 (Live).flac';
audio_info = audioinfo(audio_file);
Fs = audio_info.SampleRate; % 使用文件的真实采样率

%% 控制变量区
RateL = [];
RateR = [];
SNRcount = [];
SNR = [19, 17, 15, 12, 9, 6, 3, 0, -3, -6]; % 信噪比范围(dB)

for n = 1:1:length(SNR)
    %% 读取音频文件 - 固定读取10秒音频
    % 使用真实采样率计算10秒对应的采样点数
    samples_10s = 10 * Fs;  % 现在Fs是文件的真实采样率
    [Data, Fs_read] = audioread(audio_file, [1, samples_10s]);
    MusicLeft = Data(:, 1);   % 左声道
    MusicRight = Data(:, 2);  
    
    %% 二、ADC-量化（Quantizing）
    %% 1)左声道采用8位A律13折线法量化
    sign_ = sign(MusicLeft); % 符号函数
    MusicLeft = abs(MusicLeft); % 取绝对值
    maxs = max(MusicLeft); % 解码时会用到
    MusicLeft = MusicLeft / maxs; % 归一化
    MusicLeft = 2048 * MusicLeft; % [0,1]量化为[0,2048]
    
    %% 2)右声道采用11位均匀量化法,一共12位，1位是符号位，11位是量化
    R = zeros(2^12 + 1, 1); 
    Max = max(MusicRight); 
    Min = min(MusicRight); 
    delv = (Max - Min) / 2^12; % 均匀量化的量化间隔
    
    for g = 1:2^12+1
        R(g) = Min + delv * (g - 1); % 量化区间的端点
    end
    
    MusicRight_riser = MusicRight; 
    for i = 1:length(MusicRight) 
        for j = 1:2^12
            if MusicRight_riser(i) >= R(j) && MusicRight_riser(i) <= R(j+1)
                MusicRight_riser(i) = (R(j) + R(j+1)) / 2;
                break
            end
        end
    end
    MusicRight_riser = fix((MusicRight_riser + 1) * 4096 / 2); % 将交流信号叠加直流分量平移，把[-1,1]量化为[0,4096]
    
    %% 三、编码（Encoding）
    %% 1)左声道采用8位A律13折线法编码
    encodeL = zeros(length(MusicLeft), 8); % 储存8位编码矩阵（全零)
    
    %%%%%%%%%%%%%%%%%%%%%%参数矩阵%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    sp = [0, 16, 32, 64, 128, 256, 512, 1024]; % 段落起始值
    spmin = [1, 1, 2, 4, 8, 16, 32, 64]; % 除以16，得到每段最小的量化间隔
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    for m = 1:length(MusicLeft)
        % 符号位判断
        if sign_(m) >= 0 % 符号为正，符号位为1
            encodeL(m, 1) = 1;
        else
            if sign_(m) < 0 % 符号为负，符号位为0
                encodeL(m, 1) = 0;
            end
        end
        
        % 段落码判断
        if MusicLeft(m) > 128 && MusicLeft(m) < 2048 % 在第五段与第八段之间，段落码第一位为1
            encodeL(m, 2) = 1;
        end
        
        if (MusicLeft(m) > 32 && MusicLeft(m) < 128) || (MusicLeft(m) > 512 && MusicLeft(m) < 2048) % 在第三第四第七第八段内，段落码第二位为1
            encodeL(m, 3) = 1;
        end
        
        if (MusicLeft(m) > 16 && MusicLeft(m) < 32) || (MusicLeft(m) > 64 && MusicLeft(m) < 128) || ...
           (MusicLeft(m) > 256 && MusicLeft(m) < 512) || (MusicLeft(m) > 1024 && MusicLeft(m) < 2048) % 在第二第四第六第八段内，段落码第三位为1
            encodeL(m, 4) = 1;
        end
        
        Paragraghindex = encodeL(m, 2)*4 + encodeL(m, 3)*2 + encodeL(m, 4) + 1; % 找到位于第几段
        
        % 段内码判断
        segment_position = floor((MusicLeft(m) - sp(Paragraghindex)) / spmin(Paragraghindex)); 
        
        if segment_position == 0
            encodeL(m, (5:8)) = [0, 0, 0, 0]; % 输入为0，输出为0
        else
            k = num2str(dec2bin(segment_position-1, 4)); % 段内码编码为二进制
            encodeL(m, 5) = str2double(k(1));
            encodeL(m, 6) = str2double(k(2));
            encodeL(m, 7) = str2double(k(3));
            encodeL(m, 8) = str2double(k(4));
        end
    end
    
    %% 2)右声道采用11位均匀量化法编码
    encodeR = zeros(length(MusicRight_riser), 12); 
    
    for u = 1:length(MusicRight_riser) 
        h = num2str(dec2bin(MusicRight_riser(u), 12)); % 段内码编码为二进制
        encodeR(u, 1) = str2double(h(1));
        encodeR(u, 2) = str2double(h(2));
        encodeR(u, 3) = str2double(h(3));
        encodeR(u, 4) = str2double(h(4));
        encodeR(u, 5) = str2double(h(5));
        encodeR(u, 6) = str2double(h(6));
        encodeR(u, 7) = str2double(h(7));
        encodeR(u, 8) = str2double(h(8));
        encodeR(u, 9) = str2double(h(9));
        encodeR(u, 10) = str2double(h(10));
        encodeR(u, 11) = str2double(h(11));
        encodeR(u, 12) = str2double(h(12));
    end
    
    %% 3)转串行
    SequenceL = reshape(encodeL, 1, []); % 重构数组为1*n的序列sequence，便于串行发送
    SequenceR = reshape(encodeR, 1, []); % 重构数组为1*n的序列sequence，便于串行发送
    
    %% 四、发送端口
    VoltageSequenceL = SequenceL * 5.0; % 以TTL电平发送
    VoltageSequenceR = SequenceR * 5.0; % 以TTL电平发送
    
    %% 五、加性高斯信道
    NosiedB = SNR(n);
    NoiseSequenceL = awgn(VoltageSequenceL, NosiedB, 'measured');
    NoiseSequenceR = awgn(VoltageSequenceR, NosiedB, 'measured');
    
    % 眼图绘制优化版本（仅在SNR为19, 12, -6时绘制）
    if ismember(SNR(n), [19, 12, -6])
        % 计算当前SNR在子图中的位置
        snr_list = [19, 12, -6];
        subplot_pos = find(snr_list == SNR(n));
        
        figure(7);
        if SNR(n) == 19  % 第一个SNR时初始化figure
            clf; % 清除图形
            set(gcf, 'position', [100 100 1000 800]); % 调整窗口大小
        end
        
        subplot(3, 1, subplot_pos);
        
        % 保持原来的眼图绘制方式，但减少绘制数量和去掉延时
        for i = 2:5:1000  % 原来是1:3000，每3个点取一个
            plot(NoiseSequenceL(i:i+2));
            hold on;
        end
        
        title(sprintf('Eye Diagram (SNR = %d dB)', SNR(n)));
        xlabel('Time');
        ylabel('Amplitude');
        grid on;
        hold off;
        
        % 设置图形属性
        if SNR(n) == -6 % 最后一个子图时添加总标题
            sgtitle('不同信噪比下的眼图对比', 'FontSize', 14); % 添加总标题
        end
    end
    
    %% 六、接收端口
    %% 1)以TTL电平的一半(2.5V)进行抽样判决
    DeVoltageSequenceL = NoiseSequenceL > 2.5; % 因为是单极性波形
    DeVoltageSequenceR = NoiseSequenceR > 2.5; % 因为是单极性波形
    
    %% 2)转并行
    DeSequenceL = reshape(DeVoltageSequenceL, length(DeVoltageSequenceL)/8, 8);
    DeSequenceR = reshape(DeVoltageSequenceR, length(DeVoltageSequenceR)/12, 12);
    
    %% 3)误码率计算
    % 调用biterr函数法（备选方案）
    % [number, ratio] = biterr(DeSequenceL, encodeL);
    
    % 自写函数法计算误码率
    ErrorbitnumL = sum(sum(DeSequenceL ~= encodeL));
    ErrorbitnumR = sum(sum(DeSequenceR ~= encodeR));
    [longL, wideL] = size(DeSequenceL);
    [longR, wideR] = size(DeSequenceR);
    ErrorbitRateL = ErrorbitnumL / (longL * wideL);
    ErrorbitRateR = ErrorbitnumR / (longR * wideR);
    
    % 存储误码率结果
    RateL = [RateL, ErrorbitRateL]; %#ok<AGROW>
    RateR = [RateR, ErrorbitRateR]; %#ok<AGROW>
    SNRcount = [SNRcount, SNR(n)]; %#ok<AGROW>
    
    % 显示当前处理进度
    fprintf('SNR = %d dB: 左声道误码率 = %.6f, 右声道误码率 = %.6f\n', ...
            SNR(n), ErrorbitRateL, ErrorbitRateR);
end

%% 绘制误码率随信噪比变化曲线
figure(6);
set(gcf, 'position', [350 100 800 600]);
semilogy(SNRcount, RateL, 'b*-', 'LineWidth', 1.5, 'MarkerSize', 8);
hold on;
semilogy(SNRcount, RateR, 'ro-', 'LineWidth', 1.5, 'MarkerSize', 8);
grid on;
xlabel('信噪比 (dB)');
ylabel('误码率');
title('误码率随信噪比变化曲线');
legend('左声道: 8位A律13折线法编码', '右声道: 11位均匀量化编码', 'Location', 'best');
xlim([-8, 20]);% 设置X轴显示范围从-8到20dB
hold off;