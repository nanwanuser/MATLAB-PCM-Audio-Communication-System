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
    MusicRight = Data(:, 2);  % 右声道
    
    %% 时域图显示（仅第一次显示，因为每次都一样）
    if n == 1
        N = length(Data);
        t = (0:N-1) / Fs;
        
        figure(1);
        set(gcf, 'position', [200 480 530 300]);
        subplot(211);
        plot(t, Data);
        title('采样后的初始音频时域图');
        xlabel('Time (s)'); 
        ylabel('Amplitude');
        legend('左声道', '右声道');
        
        %% 频谱图显示
        fft_result = fft(Data, N);
        subplot(212);
        df = Fs / length(Data);
        f = 0:df:(Fs/2 - df);
        Yf = abs(fft_result);
        Yf = Yf(1:length(Yf)/2, :);
        plot(f, Yf);
        axis([0, Fs/10, 0, 300]);
        title('采样后的初始音频频谱图');
        xlabel('f/Hz'); 
        ylabel('Amplitude');
        legend('左声道', '右声道');
        pause(0.001);
    else
        % 后续循环只需要重新计算N和t，因为音频内容相同
        N = length(Data);
        t = (0:N-1) / Fs;
    end

    %% ADC量化处理
    % 左声道：8位A律13折线法量化
    sign_ = sign(MusicLeft);
    MusicLeft = abs(MusicLeft);
    maxs = max(MusicLeft); % 保存原始最大值用于恢复
    MusicLeft = MusicLeft / maxs;
    MusicLeft = 2048 * MusicLeft; % [0,1]量化为[0,2048]
    
    % 右声道：11位均匀量化法
    R = zeros(2^12 + 1, 1); % 修正：数组越界问题
    Max = max(MusicRight);
    Min = min(MusicRight);
    delv = (Max - Min) / 2^12;
    
    for g = 1:2^12+1
        R(g) = Min + delv * (g - 1);
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
    MusicRight_riser = fix((MusicRight_riser + 1) * 4096 / 2);

    %% 量化后时域图显示（仅第一次显示）
    if n == 1
        figure(2);
        set(gcf, 'position', [750 480 530 300]);
        subplot(211);
        stairs(t, MusicLeft);
        title('8位A律13折线法量化后的左声道音频时域图');
        xlabel('Time (s)'); 
        ylabel('Amplitude');
        
        subplot(212);
        stairs(t, MusicRight_riser);
        title('11位均匀量化法量化后的右声道音频时域图');
        xlabel('Time (s)'); 
        ylabel('Amplitude');
        pause(0.001);
    end

    %% 编码处理
    % 左声道：8位A律13折线法编码
    encodeL = zeros(length(MusicLeft), 8);
    sp = [0, 16, 32, 64, 128, 256, 512, 1024]; % 段落起始值
    spmin = [1, 1, 2, 4, 8, 16, 32, 64];       % 最小量化间隔
    
    for m = 1:length(MusicLeft)
        % 符号位判断
        if sign_(m) >= 0
            encodeL(m, 1) = 1;
        else
            encodeL(m, 1) = 0;
        end
        
        % 段落码判断
        if MusicLeft(m) > 128 && MusicLeft(m) < 2048
            encodeL(m, 2) = 1;
        end
        if (MusicLeft(m) > 32 && MusicLeft(m) < 128) || (MusicLeft(m) > 512 && MusicLeft(m) < 2048)
            encodeL(m, 3) = 1;
        end
        if (MusicLeft(m) > 16 && MusicLeft(m) < 32) || (MusicLeft(m) > 64 && MusicLeft(m) < 128) || ...
           (MusicLeft(m) > 256 && MusicLeft(m) < 512) || (MusicLeft(m) > 1024 && MusicLeft(m) < 2048)
            encodeL(m, 4) = 1;
        end
        
        Paragraghindex = encodeL(m, 2)*4 + encodeL(m, 3)*2 + encodeL(m, 4) + 1;
        
        % 段内码判断
        segment_position = floor((MusicLeft(m) - sp(Paragraghindex)) / spmin(Paragraghindex));
        if segment_position == 0
            encodeL(m, (5:8)) = [0, 0, 0, 0];
        else
            k = num2str(dec2bin(segment_position, 4));
            encodeL(m, 5) = str2double(k(1));
            encodeL(m, 6) = str2double(k(2));
            encodeL(m, 7) = str2double(k(3));
            encodeL(m, 8) = str2double(k(4));
        end
    end
    
    % 右声道：11位均匀量化法编码
    encodeR = zeros(length(MusicRight_riser), 12);
    for u = 1:length(MusicRight_riser)
        h = num2str(dec2bin(MusicRight_riser(u), 12));
        for bit = 1:12
            encodeR(u, bit) = str2double(h(bit));
        end
    end
    
    %% 转串行传输
    SequenceL = reshape(encodeL, 1, []);
    SequenceR = reshape(encodeR, 1, []);

    %% 发送端口处理
    VoltageSequenceL = SequenceL * 5.0; % TTL电平发送
    VoltageSequenceR = SequenceR * 5.0; % TTL电平发送
    
    %% 加性高斯信道模拟
    NosiedB = SNR(n);
    NoiseSequenceL = awgn(VoltageSequenceL, NosiedB, 'measured');
    NoiseSequenceR = awgn(VoltageSequenceR, NosiedB, 'measured');
    
    %% 加噪前后对比图 - 仅显示特定SNR情况，左右声道分开
    if ismember(SNR(n), [19, 12, -6])
        figure(3);
        if SNR(n) == 19  % 第一个SNR时初始化figure
            clf; % 清除图形
            set(gcf, 'position', [50 50 1000 800]); % 调整窗口大小适应3x2子图
        end
        
        % 计算子图位置
        snr_index = find(ismember([19, 12, -6], SNR(n)));
        plot_range = 60000:60500; % 显示范围
        
        % 左声道子图
        subplot(3, 2, snr_index*2-1);
        hold on;
        stairs(plot_range - plot_range(1) + 1, VoltageSequenceL(plot_range), 'b-', 'LineWidth', 1.2, 'DisplayName', '原信号');
        plot(plot_range - plot_range(1) + 1, NoiseSequenceL(plot_range), 'r-', 'LineWidth', 0.8, 'DisplayName', '加噪后');
        title(sprintf('左声道 SNR = %d dB', NosiedB));
        xlabel('采样点');
        ylabel('幅度 (V)');
        legend('Location', 'best', 'FontSize', 8);
        grid on;
        axis tight;
        hold off;
        
        % 右声道子图
        subplot(3, 2, snr_index*2);
        hold on;
        stairs(plot_range - plot_range(1) + 1, VoltageSequenceR(plot_range), 'g-', 'LineWidth', 1.2, 'DisplayName', '原信号');
        plot(plot_range - plot_range(1) + 1, NoiseSequenceR(plot_range), 'm-', 'LineWidth', 0.8, 'DisplayName', '加噪后');
        title(sprintf('右声道 SNR = %d dB', NosiedB));
        xlabel('采样点');
        ylabel('幅度 (V)');
        legend('Location', 'best', 'FontSize', 8);
        grid on;
        axis tight;
        hold off;
        
        if SNR(n) == -6  % 最后一个SNR时添加总标题
            sgtitle('不同信噪比下的加噪前后对比', 'FontSize', 14);
        end
        
        pause(0.01); % 短暂暂停以便观察绘制过程
    end

    %% 接收端口处理
    % TTL电平判决(2.5V)
    DeVoltageSequenceL = NoiseSequenceL > 2.5;
    DeVoltageSequenceR = NoiseSequenceR > 2.5;
    
    % 转并行
    DeSequenceL = reshape(DeVoltageSequenceL, length(DeVoltageSequenceL)/8, 8);
    DeSequenceR = reshape(DeVoltageSequenceR, length(DeVoltageSequenceR)/12, 12);

    %% 译码处理
    % 左声道译码
    decodeL = zeros(length(DeSequenceL), 1);
    for s = 1:length(DeSequenceL)
        % 确定符号
        if DeSequenceL(s, 1) == 1
            Polarity = 1;
        else
            Polarity = -1;
        end
        
        % 确定段落
        Paragraghindex = DeSequenceL(s, 2)*4 + DeSequenceL(s, 3)*2 + DeSequenceL(s, 4) + 1;
        
        % 确定段内位置
        decode_position = bin2dec(num2str(DeSequenceL(s, (5:8))));
        
        % 计算量化电平值
        decodeL(s, 1) = Polarity * (sp(Paragraghindex) + spmin(Paragraghindex) * (decode_position + 0.5));
    end
    
    % 右声道译码
    decodeR = zeros(length(DeSequenceR), 1);
    for f = 1:length(DeSequenceR)
        decodeR(f) = bin2dec(num2str(DeSequenceR(f, (1:12))));
    end

    %% DAC生成交流信号
    % 左声道
    decodeL = decodeL / 2048;
    MusicoutL = decodeL * maxs;
    
    % 右声道
    MusicoutR = (decodeR / 4096.0) * 2 - 1;

    %% 低通滤波器处理
    B = 0.0079 * [1, 5, 10, 5, 1];
    A = [1, -2.2188, 3.0019, -2.4511, 1.2330, -0.3109];
    
    MusicfilteroutL = filter(B, A, MusicoutL);
    MusicfilteroutR = filter(B, A, MusicoutR);
    
    %% 数据归一化处理（防止裁剪）
    % 左声道归一化
    max_val_L = max(abs(MusicfilteroutL));
    if max_val_L > 1
        MusicfilteroutL = MusicfilteroutL / max_val_L * 0.95; % 留5%余量
    end
    
    % 右声道归一化
    max_val_R = max(abs(MusicfilteroutR));
    if max_val_R > 1
        MusicfilteroutR = MusicfilteroutR / max_val_R * 0.95; % 留5%余量
    end
    
    %% 显示滤波后结果（仅在特定SNR时显示）
    if ismember(SNR(n), [19, 12, -6]) % 只显示高、中、低三种SNR的结果
        figure(4);
        subplot(3, 2, find(ismember([19, 12, -6], SNR(n)))*2-1);
        plot(t, MusicfilteroutL);
        title(sprintf('滤波后左声道 (SNR=%ddB)', SNR(n)));
        xlabel('Time (s)'); 
        ylabel('Amplitude');
        grid on;
        
        subplot(3, 2, find(ismember([19, 12, -6], SNR(n)))*2);
        plot(t, MusicfilteroutR);
        title(sprintf('滤波后右声道 (SNR=%ddB)', SNR(n)));
        xlabel('Time (s)'); 
        ylabel('Amplitude');
        grid on;
        
        if SNR(n) == -6
            set(gcf, 'position', [750 45 800 600]);
            sgtitle('不同SNR下的低通滤波输出对比');
        end
    end
    
    %% 文件输出
    % 创建输出文件夹
    output_dir = 'music_output';
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
    end
    
    % 生成文件名并输出到指定文件夹
    nameL = fullfile(output_dir, sprintf('Nanwan_%ddB_left_channel.wav', NosiedB));
    nameR = fullfile(output_dir, sprintf('Nanwan_%ddB_right_channel.wav', NosiedB));
    
    % 写入音频文件（数据已归一化，不会被裁剪）
    audiowrite(nameL, MusicfilteroutL, Fs);
    audiowrite(nameR, MusicfilteroutR, Fs);
    
    % 显示处理进度
    fprintf('已完成 SNR = %d dB 的处理 (%d/%d)\n', NosiedB, n, length(SNR));
    
end

fprintf('所有音频文件已保存完成\n');