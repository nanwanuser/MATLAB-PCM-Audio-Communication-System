classdef PCM_App < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure                matlab.ui.Figure
        ImportAudioMenu         matlab.ui.container.Menu
        StartProcessingBtn      matlab.ui.control.Button
        StartSamplingBtn        matlab.ui.control.Button
        PlotBERCurveBtn         matlab.ui.control.Button
        PlotFilteredOutputBtn   matlab.ui.control.Button
        PlotEyeDiagramBtn       matlab.ui.control.Button
        PlotQuantizedSignalBtn  matlab.ui.control.Button
        PlotNoiseComparisonBtn  matlab.ui.control.Button
        SNRGroupDropdown        matlab.ui.control.DropDown
        Label_2                 matlab.ui.control.Label
        AudioFilePathEdit       matlab.ui.control.EditField
        Label                   matlab.ui.control.Label
        FrequencyDomainAxes     matlab.ui.control.UIAxes
        TimeDomainAxes          matlab.ui.control.UIAxes
    end


    % Public properties that correspond to the Simulink model
    properties (Access = public, Transient)
        Simulation simulink.Simulation
    end

    

    properties (Access = public)
        % 音频数据
        AudioData           % 原始音频数据
        AudioFs             % 采样频率
        AudioLeftChannel    % 左声道数据
        AudioRightChannel   % 右声道数据
        
        % 编码数据
        EncodedLeftData     % 左声道编码数据
        EncodedRightData    % 右声道编码数据
        
        % 传输数据
        NoiseSequenceL      % 左声道加噪数据
        NoiseSequenceR      % 右声道加噪数据
        
        % 解码数据
        DecodedLeftData     % 左声道解码数据
        DecodedRightData    % 右声道解码数据
        
        % 滤波数据
        FilteredLeftData    % 左声道滤波数据
        FilteredRightData   % 右声道滤波数据
        
        % 性能数据
        BERLeftData         % 左声道误码率数据
        BERRightData        % 右声道误码率数据
        SNRValues           % 信噪比数组
        
        % 处理标志
        IsAudioLoaded = false       % 音频是否已加载
        IsProcessingComplete = false % 处理是否完成
        IsCancelled = false         % 是否已取消处理
        
        % 进度对话框
        ProgressDialog      % 进度对话框句柄
    end
    
    methods (Access = public)
        
        %% 辅助函数定义（根据main.m中的具体实现）

        function [berL, berR] = processAudioAtSNR(app, snr, progressCallback)
            % 完整的PCM编码传输处理流程，支持进度回调和中断检查
            
            if app.IsCancelled
                berL = 0; berR = 0;
                return;
            end
            
            MusicLeft = app.AudioLeftChannel;
            MusicRight = app.AudioRightChannel;
            Fs = app.AudioFs;
            
            %% A律量化与编码（左声道）
            if exist('progressCallback', 'var') && isa(progressCallback, 'function_handle')
                progressCallback(0.1, sprintf('SNR %ddB: A律量化处理中...', snr));
            end
            
            if app.IsCancelled, berL = 0; berR = 0; return; end
            
            sign_ = sign(MusicLeft);
            MusicLeft = abs(MusicLeft);
            maxs = max(MusicLeft);
            MusicLeft = MusicLeft / maxs;
            MusicLeft = 2048 * MusicLeft;
            
            % A律编码
            encodeL = zeros(length(MusicLeft), 8);
            sp = [0, 16, 32, 64, 128, 256, 512, 1024];
            spmin = [1, 1, 2, 4, 8, 16, 32, 64];
            
            total_samples = length(MusicLeft);
            for m = 1:total_samples
                % 定期检查是否取消和更新进度
                if mod(m, round(total_samples/10)) == 0
                    if app.IsCancelled, berL = 0; berR = 0; return; end
                    if exist('progressCallback', 'var') && isa(progressCallback, 'function_handle')
                        progress = 0.1 + 0.3 * (m/total_samples);
                        progressCallback(progress, sprintf('SNR %ddB: A律编码进度 %.1f%%', snr, m/total_samples*100));
                    end
                end
                
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
            
            %% 均匀量化与编码（右声道）
            if exist('progressCallback', 'var') && isa(progressCallback, 'function_handle')
                progressCallback(0.4, sprintf('SNR %ddB: 均匀量化处理中...', snr));
            end
            
            if app.IsCancelled, berL = 0; berR = 0; return; end
            
            R = zeros(2^12 + 1, 1);
            Max = max(MusicRight);
            Min = min(MusicRight);
            delv = (Max - Min) / 2^12;
            
            for g = 1:2^12+1
                R(g) = Min + delv * (g - 1);
            end
            
            MusicRight_riser = MusicRight;
            total_right_samples = length(MusicRight);
            for i = 1:total_right_samples
                % 定期检查是否取消和更新进度
                if mod(i, round(total_right_samples/10)) == 0
                    if app.IsCancelled, berL = 0; berR = 0; return; end
                    if exist('progressCallback', 'var') && isa(progressCallback, 'function_handle')
                        progress = 0.4 + 0.2 * (i/total_right_samples);
                        progressCallback(progress, sprintf('SNR %ddB: 均匀量化进度 %.1f%%', snr, i/total_right_samples*100));
                    end
                end
                
                for j = 1:2^12
                    if MusicRight_riser(i) >= R(j) && MusicRight_riser(i) <= R(j+1)
                        MusicRight_riser(i) = (R(j) + R(j+1)) / 2;
                        break
                    end
                end
            end
            MusicRight_riser = fix((MusicRight_riser + 1) * 4096 / 2);
            
            % 右声道编码
            if exist('progressCallback', 'var') && isa(progressCallback, 'function_handle')
                progressCallback(0.6, sprintf('SNR %ddB: 右声道编码中...', snr));
            end
            
            if app.IsCancelled, berL = 0; berR = 0; return; end
            
            encodeR = zeros(length(MusicRight_riser), 12);
            for u = 1:length(MusicRight_riser)
                % 定期检查是否取消
                if mod(u, round(length(MusicRight_riser)/5)) == 0
                    if app.IsCancelled, berL = 0; berR = 0; return; end
                    if exist('progressCallback', 'var') && isa(progressCallback, 'function_handle')
                        progress = 0.6 + 0.1 * (u/length(MusicRight_riser));
                        progressCallback(progress, sprintf('SNR %ddB: 右声道编码进度 %.1f%%', snr, u/length(MusicRight_riser)*100));
                    end
                end
                
                h = num2str(dec2bin(MusicRight_riser(u), 12));
                for bit = 1:12
                    encodeR(u, bit) = str2double(h(bit));
                end
            end
            
            %% 串行传输
            if exist('progressCallback', 'var') && isa(progressCallback, 'function_handle')
                progressCallback(0.7, sprintf('SNR %ddB: 串行传输处理中...', snr));
            end
            
            if app.IsCancelled, berL = 0; berR = 0; return; end
            
            SequenceL = reshape(encodeL, 1, []);
            SequenceR = reshape(encodeR, 1, []);
            
            %% TTL电平转换
            VoltageSequenceL = SequenceL * 5.0;
            VoltageSequenceR = SequenceR * 5.0;
            
            %% 加性高斯白噪声信道
            if exist('progressCallback', 'var') && isa(progressCallback, 'function_handle')
                progressCallback(0.75, sprintf('SNR %ddB: 添加高斯噪声中...', snr));
            end
            
            if app.IsCancelled, berL = 0; berR = 0; return; end
            
            app.NoiseSequenceL = awgn(VoltageSequenceL, snr, 'measured');
            app.NoiseSequenceR = awgn(VoltageSequenceR, snr, 'measured');
            
            %% 接收端处理
            if exist('progressCallback', 'var') && isa(progressCallback, 'function_handle')
                progressCallback(0.8, sprintf('SNR %ddB: 接收端处理中...', snr));
            end
            
            if app.IsCancelled, berL = 0; berR = 0; return; end
            
            % TTL电平判决
            DeVoltageSequenceL = app.NoiseSequenceL > 2.5;
            DeVoltageSequenceR = app.NoiseSequenceR > 2.5;
            
            % 转并行
            DeSequenceL = reshape(DeVoltageSequenceL, length(DeVoltageSequenceL)/8, 8);
            DeSequenceR = reshape(DeVoltageSequenceR, length(DeVoltageSequenceR)/12, 12);
            
            %% 误码率计算
            if exist('progressCallback', 'var') && isa(progressCallback, 'function_handle')
                progressCallback(0.9, sprintf('SNR %ddB: 误码率计算中...', snr));
            end
            
            if app.IsCancelled, berL = 0; berR = 0; return; end
            
            ErrorbitnumL = sum(sum(DeSequenceL ~= encodeL));
            ErrorbitnumR = sum(sum(DeSequenceR ~= encodeR));
            [longL, wideL] = size(DeSequenceL);
            [longR, wideR] = size(DeSequenceR);
            berL = ErrorbitnumL / (longL * wideL);
            berR = ErrorbitnumR / (longR * wideR);
            
            %% 存储中间结果到app属性
            app.EncodedLeftData = encodeL;
            app.EncodedRightData = encodeR;
            
            if exist('progressCallback', 'var') && isa(progressCallback, 'function_handle')
                progressCallback(1.0, sprintf('SNR %ddB: 完成', snr));
            end
        end

        function [quantizedData] = performALawQuantization(~, audioData)
            % A律量化实现
            sign_ = sign(audioData);
            audioData = abs(audioData);
            maxs = max(audioData);
            audioData = audioData / maxs;
            quantizedData = 2048 * audioData;
        end

        function [quantizedData] = performUniformQuantization(~, audioData)
            % 均匀量化实现
            R = zeros(2^12 + 1, 1);
            Max = max(audioData);
            Min = min(audioData);
            delv = (Max - Min) / 2^12;
            
            for g = 1:2^12+1
                R(g) = Min + delv * (g - 1);
            end
            
            quantizedData = audioData;
            for i = 1:length(audioData)
                for j = 1:2^12
                    if quantizedData(i) >= R(j) && quantizedData(i) <= R(j+1)
                        quantizedData(i) = (R(j) + R(j+1)) / 2;
                        break
                    end
                end
            end
            quantizedData = fix((quantizedData + 1) * 4096 / 2);
        end

        function [noisyLeft, noisyRight, cleanLeft, cleanRight] = generateNoisySignals(app, snr)
            % 生成加噪信号（重现编码传输过程）
            
            % 获取编码后的TTL电平信号
            MusicLeft = app.AudioLeftChannel;
            MusicRight = app.AudioRightChannel;
            
            % A律编码处理
            sign_ = sign(MusicLeft);
            MusicLeft = abs(MusicLeft);
            maxs = max(MusicLeft);
            MusicLeft = MusicLeft / maxs;
            MusicLeft = 2048 * MusicLeft;
            
            % A律编码
            encodeL = zeros(length(MusicLeft), 8);
            sp = [0, 16, 32, 64, 128, 256, 512, 1024];
            spmin = [1, 1, 2, 4, 8, 16, 32, 64];
            
            for m = 1:length(MusicLeft)
                if sign_(m) >= 0
                    encodeL(m, 1) = 1;
                else
                    encodeL(m, 1) = 0;
                end
                
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
            
            % 右声道均匀量化编码
            R = zeros(2^12 + 1, 1);
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
            
            encodeR = zeros(length(MusicRight_riser), 12);
            for u = 1:length(MusicRight_riser)
                h = num2str(dec2bin(MusicRight_riser(u), 12));
                for bit = 1:12
                    encodeR(u, bit) = str2double(h(bit));
                end
            end
            
            % 转串行和TTL电平
            SequenceL = reshape(encodeL, 1, []);
            SequenceR = reshape(encodeR, 1, []);
            cleanLeft = SequenceL * 5.0;
            cleanRight = SequenceR * 5.0;
            
            % 添加噪声
            noisyLeft = awgn(cleanLeft, snr, 'measured');
            noisyRight = awgn(cleanRight, snr, 'measured');
        end

        function [filteredLeft, filteredRight] = getFilteredSignals(app, snr)
            % 获取滤波后信号（完整的解码和滤波流程）
            
            % 重新进行编码传输解码流程
            MusicLeft = app.AudioLeftChannel;
            MusicRight = app.AudioRightChannel;
            
            % 编码过程（与processAudioAtSNR相同）
            sign_ = sign(MusicLeft);
            MusicLeft = abs(MusicLeft);
            maxs = max(MusicLeft);
            MusicLeft = MusicLeft / maxs;
            MusicLeft = 2048 * MusicLeft;
            
            % A律编码
            encodeL = zeros(length(MusicLeft), 8);
            sp = [0, 16, 32, 64, 128, 256, 512, 1024];
            spmin = [1, 1, 2, 4, 8, 16, 32, 64];
            
            for m = 1:length(MusicLeft)
                if sign_(m) >= 0
                    encodeL(m, 1) = 1;
                else
                    encodeL(m, 1) = 0;
                end
                
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
            
            % 右声道编码（同上）
            R = zeros(2^12 + 1, 1);
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
            
            encodeR = zeros(length(MusicRight_riser), 12);
            for u = 1:length(MusicRight_riser)
                h = num2str(dec2bin(MusicRight_riser(u), 12));
                for bit = 1:12
                    encodeR(u, bit) = str2double(h(bit));
                end
            end
            
            % 传输和接收
            SequenceL = reshape(encodeL, 1, []);
            SequenceR = reshape(encodeR, 1, []);
            VoltageSequenceL = SequenceL * 5.0;
            VoltageSequenceR = SequenceR * 5.0;
            
            app.NoiseSequenceL = awgn(VoltageSequenceL, snr, 'measured');
            app.NoiseSequenceR = awgn(VoltageSequenceR, snr, 'measured');
            
            DeVoltageSequenceL = app.NoiseSequenceL > 2.5;
            DeVoltageSequenceR = app.NoiseSequenceR > 2.5;
            
            DeSequenceL = reshape(DeVoltageSequenceL, length(DeVoltageSequenceL)/8, 8);
            DeSequenceR = reshape(DeVoltageSequenceR, length(DeVoltageSequenceR)/12, 12);
            
            % A律解码
            decodeL = zeros(length(DeSequenceL), 1);
            for s = 1:length(DeSequenceL)
                if DeSequenceL(s, 1) == 1
                    Polarity = 1;
                else
                    Polarity = -1;
                end
                
                Paragraghindex = DeSequenceL(s, 2)*4 + DeSequenceL(s, 3)*2 + DeSequenceL(s, 4) + 1;
                decode_position = bin2dec(num2str(DeSequenceL(s, (5:8))));
                decodeL(s, 1) = Polarity * (sp(Paragraghindex) + spmin(Paragraghindex) * (decode_position + 0.5));
            end
            
            % 均匀量化解码
            decodeR = zeros(length(DeSequenceR), 1);
            for f = 1:length(DeSequenceR)
                decodeR(f) = bin2dec(num2str(DeSequenceR(f, (1:12))));
            end
            
            % DAC重建
            decodeL = decodeL / 2048;
            MusicoutL = decodeL * maxs;
            MusicoutR = (decodeR / 4096.0) * 2 - 1;
            
            % 低通滤波器
            B = 0.0079 * [1, 5, 10, 5, 1];
            A = [1, -2.2188, 3.0019, -2.4511, 1.2330, -0.3109];
            
            filteredLeft = filter(B, A, MusicoutL);
            filteredRight = filter(B, A, MusicoutR);
            
            % 数据归一化处理
            max_val_L = max(abs(filteredLeft));
            if max_val_L > 1
                filteredLeft = filteredLeft / max_val_L * 0.95;
            end
            
            max_val_R = max(abs(filteredRight));
            if max_val_R > 1
                filteredRight = filteredRight / max_val_R * 0.95;
            end
        end

        function updateProgress(app, currentSNR, totalSNR, subProgress, message)
            % 更新进度对话框
            if isvalid(app.ProgressDialog) && ~app.IsCancelled
                % 计算总体进度
                overallProgress = (currentSNR - 1) / totalSNR + subProgress / totalSNR;
                app.ProgressDialog.Value = overallProgress;
                app.ProgressDialog.Message = message;
                
                % 检查是否被取消
                if app.ProgressDialog.CancelRequested
                    app.IsCancelled = true;
                end
                
                % 允许GUI更新
                drawnow;
            end
        end
    end
    

    % Callbacks that handle component events
    methods (Access = private)

        % Menu selected function: ImportAudioMenu
        function ImportAudioMenuSelected(app, event)
            [filename, pathname] = uigetfile({'*.wav;*.flac;*.mp3;*.m4a'}, '选择音频文件');
            if isequal(filename, 0) || isequal(pathname, 0)
                return;
            end
            
            % 更新文件路径显示
            app.AudioFilePathEdit.Value = [pathname, filename];
            
            % 读取音频文件信息
            audio_file = [pathname, filename];
            audio_info = audioinfo(audio_file);
            app.AudioFs = audio_info.SampleRate;
            
            % 读取10秒音频数据
            samples_10s = 10 * app.AudioFs;
            [app.AudioData, ~] = audioread(audio_file, [1, min(samples_10s, audio_info.TotalSamples)]);
            
            % 分离左右声道
            if size(app.AudioData, 2) == 2
                app.AudioLeftChannel = app.AudioData(:, 1);
                app.AudioRightChannel = app.AudioData(:, 2);
            else
                app.AudioLeftChannel = app.AudioData;
                app.AudioRightChannel = app.AudioData;
            end
            
            app.IsAudioLoaded = true;
            
            % 显示成功消息
            uialert(app.UIFigure, sprintf('音频文件加载成功！\n采样率: %d Hz\n时长: %.2f 秒', ...
                app.AudioFs, length(app.AudioLeftChannel)/app.AudioFs), '加载成功', 'Icon', 'success');
        end

        % Button pushed function: StartSamplingBtn
        function StartSamplingBtnPushed(app, event)
            
            if ~app.IsAudioLoaded
                uialert(app.UIFigure, '请先选择音频文件！', '错误', 'Icon', 'error');
                return;
            end
            
            % 绘制时域图
            N = length(app.AudioLeftChannel);
            t = (0:N-1) / app.AudioFs;
            
            plot(app.TimeDomainAxes, t, app.AudioLeftChannel, t, app.AudioRightChannel);
            app.TimeDomainAxes.Title.String = '采样后的初始音频时域图';
            app.TimeDomainAxes.XLabel.String = 'Time (s)';
            app.TimeDomainAxes.YLabel.String = 'Amplitude';
            legend(app.TimeDomainAxes, '左声道', '右声道');
            
            % 绘制频域图
            Y = fft(app.AudioData);
            df = app.AudioFs / length(app.AudioData);
            f = 0:df:(app.AudioFs/2 - df);
            Yf = abs(Y);
            Yf = Yf(1:length(Yf)/2, :);
            
            plot(app.FrequencyDomainAxes, f, Yf);
            app.FrequencyDomainAxes.Title.String = '采样后的初始音频频域图';
            app.FrequencyDomainAxes.XLabel.String = 'f/Hz';
            app.FrequencyDomainAxes.YLabel.String = 'Amplitude';
            app.FrequencyDomainAxes.XLim = [0, app.AudioFs/10];
            app.FrequencyDomainAxes.YLim = [0, 300];
            legend(app.FrequencyDomainAxes, '左声道', '右声道');
            
        end

        % Button pushed function: StartProcessingBtn
        function StartProcessingBtnPushed(app, event)

            if ~app.IsAudioLoaded
                uialert(app.UIFigure, '请先加载音频文件并采样！', '错误', 'Icon', 'error');
                return;
            end
            
            % 重置取消标志
            app.IsCancelled = false;
            
            % 创建带取消按钮的进度对话框
            app.ProgressDialog = uiprogressdlg(app.UIFigure, 'Title', '正在处理...', ...
                'Message', '初始化处理参数', 'Cancelable', true, 'CancelText', '取消处理');
            
            try
                % 使用完整的信噪比数组
                app.SNRValues = [19, 17, 15, 12, 9, 6, 3, 0, -3, -6];
                
                % 初始化性能数据存储
                app.BERLeftData = [];
                app.BERRightData = [];
                
                total_snr_count = length(app.SNRValues);
                
                % 对每个信噪比进行处理
                for i = 1:total_snr_count
                    % 检查是否被取消
                    if app.ProgressDialog.CancelRequested || app.IsCancelled
                        app.IsCancelled = true;
                        close(app.ProgressDialog);
                        uialert(app.UIFigure, '处理已被用户取消！', '处理取消', 'Icon', 'warning');
                        return;
                    end
                    
                    current_snr = app.SNRValues(i);
                    
                    % 创建进度回调函数
                    progressCallback = @(subProgress, message) updateProgress(app, i, total_snr_count, subProgress, message);
                    
                    % 调用主处理函数
                    [berL, berR] = processAudioAtSNR(app, current_snr, progressCallback);
                    
                    % 检查是否被取消
                    if app.IsCancelled
                        close(app.ProgressDialog);
                        uialert(app.UIFigure, '处理已被用户取消！', '处理取消', 'Icon', 'warning');
                        return;
                    end
                    
                    app.BERLeftData = [app.BERLeftData, berL];
                    app.BERRightData = [app.BERRightData, berR];
                    
                    % 在SNR之间稍微暂停，让用户看到进度
                    pause(0.1);
                end
                
                app.IsProcessingComplete = true;
                close(app.ProgressDialog);
                uialert(app.UIFigure, '所有信噪比的音频处理完成！', '处理完成', 'Icon', 'success');
                
            catch ME
                if isvalid(app.ProgressDialog)
                    close(app.ProgressDialog);
                end
                if ~app.IsCancelled
                    uialert(app.UIFigure, ['处理过程中出错: ' ME.message], '错误', 'Icon', 'error');
                end
            end
            
        end

        % Button pushed function: PlotQuantizedSignalBtn
        function PlotQuantizedSignalBtnPushed(app, event)
              
             if ~app.IsProcessingComplete
                uialert(app.UIFigure, '请先完成音频处理！', '错误', 'Icon', 'error');
                return;
            end
            
            % 显示进度条
            d = uiprogressdlg(app.UIFigure, 'Title', '正在绘制量化图...', 'Message', '准备数据中...', 'Cancelable', true);
            
            try
                % 创建新图窗显示量化后的时域图
                d.Value = 0.1;
                d.Message = '创建图窗...';
                if d.CancelRequested, close(d); return; end
                
                figure('Name', '量化后的时域图', 'Position', [200, 200, 800, 600]);
                
                % 重新进行量化处理以获取量化后的数据
                d.Value = 0.3;
                d.Message = '计算时间轴...';
                if d.CancelRequested, close(d); return; end
                
                N = length(app.AudioLeftChannel);
                t = (0:N-1) / app.AudioFs;
                
                % 左声道A律量化
                d.Value = 0.5;
                d.Message = '处理左声道A律量化...';
                if d.CancelRequested, close(d); return; end
                
                [quantizedLeft] = performALawQuantization(app, app.AudioLeftChannel);
                
                % 右声道均匀量化  
                d.Value = 0.7;
                d.Message = '处理右声道均匀量化...';
                if d.CancelRequested, close(d); return; end
                
                [quantizedRight] = performUniformQuantization(app, app.AudioRightChannel);
                
                % 绘制图形
                d.Value = 0.9;
                d.Message = '绘制图形...';
                if d.CancelRequested, close(d); return; end
                
                subplot(2,1,1);
                stairs(t, quantizedLeft);
                title('8位A律13折线法量化后的左声道音频时域图');
                xlabel('Time (s)');
                ylabel('Amplitude');
                
                subplot(2,1,2);
                stairs(t, quantizedRight);
                title('11位均匀量化法量化后的右声道音频时域图');
                xlabel('Time (s)');
                ylabel('Amplitude');
                
                d.Value = 1;
                d.Message = '完成！';
                close(d);
                
            catch ME
                close(d);
                if ~contains(ME.message, 'Cancel')
                    uialert(app.UIFigure, ['绘制过程中出错: ' ME.message], '错误', 'Icon', 'error');
                end
            end
            
        end

        % Button pushed function: PlotNoiseComparisonBtn
        function PlotNoiseComparisonBtnPushed(app, event)
                                          
            if ~app.IsProcessingComplete
                uialert(app.UIFigure, '请先完成音频处理！', '错误', 'Icon', 'error');
                return;
            end
            
            % 显示进度条
            d = uiprogressdlg(app.UIFigure, 'Title', '正在绘制加噪对比图...', 'Message', '初始化...', 'Cancelable', true);
            
            try
                % 获取选择的信噪比组进行显示
                snr_group = app.SNRGroupDropdown.Value;
                switch snr_group
                    case '[19,15,-6]'
                        display_snrs = [19, 15, -6];
                    case '[19,12,-6]'
                        display_snrs = [19, 12, -6];
                    case '[19,9,-6]'
                        display_snrs = [19, 9, -6];
                    case '[19,6,-6]'
                        display_snrs = [19, 6, -6];
                    case '全部SNR'
                        display_snrs = app.SNRValues;
                end
                
                % 创建新图窗显示加噪前后对比
                d.Value = 0.05;
                d.Message = '创建图窗...';
                if d.CancelRequested, close(d); return; end
                
                figure('Name', '不同信噪比下的加噪前后对比', 'Position', [100, 100, 1000, 800]);
                
                % 为选定的SNR值生成加噪对比图
                total_steps = length(display_snrs);
                for i = 1:total_steps
                    % 更新进度
                    progress = 0.05 + (i-1)/total_steps * 0.8;
                    d.Value = progress;
                    d.Message = sprintf('处理信噪比 %d dB (%d/%d)...', display_snrs(i), i, total_steps);
                    if d.CancelRequested, close(d); return; end
                    
                    snr = display_snrs(i);
                    
                    % 重新生成该SNR下的加噪信号
                    [noisyLeft, noisyRight, cleanLeft, cleanRight] = generateNoisySignals(app, snr);
                    
                    % 显示部分信号用于对比
                    plot_range = 60000:60500;
                    
                    % 左声道子图
                    subplot(3, 2, i*2-1);
                    hold on;
                    stairs(plot_range - plot_range(1) + 1, cleanLeft(plot_range), 'b-', 'LineWidth', 1.2, 'DisplayName', '原信号');
                    plot(plot_range - plot_range(1) + 1, noisyLeft(plot_range), 'r-', 'LineWidth', 0.8, 'DisplayName', '加噪后');
                    title(sprintf('左声道 SNR = %d dB', snr));
                    xlabel('采样点');
                    ylabel('幅度 (V)');
                    legend('Location', 'best', 'FontSize', 8);
                    grid on;
                    axis tight;
                    hold off;
                    
                    % 右声道子图
                    subplot(3, 2, i*2);
                    hold on;
                    stairs(plot_range - plot_range(1) + 1, cleanRight(plot_range), 'g-', 'LineWidth', 1.2, 'DisplayName', '原信号');
                    plot(plot_range - plot_range(1) + 1, noisyRight(plot_range), 'm-', 'LineWidth', 0.8, 'DisplayName', '加噪后');
                    title(sprintf('右声道 SNR = %d dB', snr));
                    xlabel('采样点');
                    ylabel('幅度 (V)');
                    legend('Location', 'best', 'FontSize', 8);
                    grid on;
                    axis tight;
                    hold off;
                end
                
                d.Value = 0.95;
                d.Message = '添加标题...';
                if d.CancelRequested, close(d); return; end
                
                sgtitle('不同信噪比下的加噪前后对比', 'FontSize', 14);
                
                d.Value = 1;
                d.Message = '完成！';
                close(d);
                
            catch ME
                close(d);
                if ~contains(ME.message, 'Cancel')
                    uialert(app.UIFigure, ['绘制过程中出错: ' ME.message], '错误', 'Icon', 'error');
                end
            end
            
        end

        % Button pushed function: PlotEyeDiagramBtn
        function PlotEyeDiagramBtnPushed(app, event)
                            
            if ~app.IsProcessingComplete
                uialert(app.UIFigure, '请先完成音频处理！', '错误', 'Icon', 'error');
                return;
            end
            
            % 显示进度条
            d = uiprogressdlg(app.UIFigure, 'Title', '正在绘制眼图...', 'Message', '初始化...', 'Cancelable', true);
            
            try
                % 获取选择的信噪比组进行显示
                snr_group = app.SNRGroupDropdown.Value;
                switch snr_group
                    case '[19,15,-6]'
                        display_snrs = [19, 15, -6];
                    case '[19,12,-6]'
                        display_snrs = [19, 12, -6];
                    case '[19,9,-6]'
                        display_snrs = [19, 9, -6];
                    case '[19,6,-6]'
                        display_snrs = [19, 6, -6];
                    case '全部SNR'
                        display_snrs = app.SNRValues;
                end
                
                % 创建新图窗显示眼图
                d.Value = 0.05;
                d.Message = '创建图窗...';
                if d.CancelRequested, close(d); return; end
                
                figure('Name', '不同信噪比下的眼图对比', 'Position', [150, 150, 1000, 800]);
                
                total_steps = length(display_snrs);
                for i = 1:total_steps
                    % 更新进度 - 主要进度在数据生成
                    progress = 0.05 + (i-1)/total_steps * 0.7;
                    d.Value = progress;
                    d.Message = sprintf('生成信噪比 %d dB 的眼图数据 (%d/%d)...', display_snrs(i), i, total_steps);
                    if d.CancelRequested, close(d); return; end
                    
                    snr = display_snrs(i);
                    
                    % 重新生成该SNR下的含噪信号
                    [noisyLeft, ~, ~, ~] = generateNoisySignals(app, snr);
                    
                    % 更新进度 - 绘制阶段
                    progress = 0.05 + (i-1)/total_steps * 0.7 + 0.2/total_steps;
                    d.Value = progress;
                    d.Message = sprintf('绘制信噪比 %d dB 的眼图 (%d/%d)...', snr, i, total_steps);
                    if d.CancelRequested, close(d); return; end
                    
                    subplot(3, 1, i);
                    
                    % 绘制眼图
                    for j = 2:5:1000
                        plot(noisyLeft(j:j+2));
                        hold on;
                    end
                    
                    title(sprintf('Eye Diagram (SNR = %d dB)', snr));
                    xlabel('Time');
                    ylabel('Amplitude');
                    grid on;
                    hold off;
                end
                
                d.Value = 0.95;
                d.Message = '添加标题...';
                if d.CancelRequested, close(d); return; end
                
                sgtitle('不同信噪比下的眼图对比', 'FontSize', 14);
                
                d.Value = 1;
                d.Message = '完成！';
                close(d);
                
            catch ME
                close(d);
                if ~contains(ME.message, 'Cancel')
                    uialert(app.UIFigure, ['绘制过程中出错: ' ME.message], '错误', 'Icon', 'error');
                end
            end
            
        end

        % Button pushed function: PlotFilteredOutputBtn
        function PlotFilteredOutputBtnPushed(app, event)
                            
            if ~app.IsProcessingComplete
                uialert(app.UIFigure, '请先完成音频处理！', '错误', 'Icon', 'error');
                return;
            end
            
            % 显示进度条
            d = uiprogressdlg(app.UIFigure, 'Title', '正在绘制滤波输出图...', 'Message', '初始化...', 'Cancelable', true);
            
            try
                % 获取选择的信噪比组进行显示
                snr_group = app.SNRGroupDropdown.Value;
                switch snr_group
                    case '[19,15,-6]'
                        display_snrs = [19, 15, -6];
                    case '[19,12,-6]'
                        display_snrs = [19, 12, -6];
                    case '[19,9,-6]'
                        display_snrs = [19, 9, -6];
                    case '[19,6,-6]'
                        display_snrs = [19, 6, -6];
                    case '全部SNR'
                        display_snrs = app.SNRValues;
                end
                
                % 创建新图窗显示滤波后输出对比
                d.Value = 0.05;
                d.Message = '创建图窗...';
                if d.CancelRequested, close(d); return; end
                
                figure('Name', '不同SNR下的低通滤波输出对比', 'Position', [200, 100, 800, 600]);
                
                total_steps = length(display_snrs);
                for i = 1:total_steps
                    % 更新进度 - 主要时间在完整处理流程
                    progress = 0.05 + (i-1)/total_steps * 0.8;
                    d.Value = progress;
                    d.Message = sprintf('完整处理信噪比 %d dB (%d/%d)...', display_snrs(i), i, total_steps);
                    if d.CancelRequested, close(d); return; end
                    
                    snr = display_snrs(i);
                    
                    % 重新进行完整的处理流程获取滤波后信号
                    [filteredLeft, filteredRight] = getFilteredSignals(app, snr);
                    
                    % 更新进度 - 绘制阶段
                    progress = 0.05 + (i-1)/total_steps * 0.8 + 0.1/total_steps;
                    d.Value = progress;
                    d.Message = sprintf('绘制信噪比 %d dB 的滤波结果 (%d/%d)...', snr, i, total_steps);
                    if d.CancelRequested, close(d); return; end
                    
                    % 绘制滤波后的时域信号
                    N = length(filteredLeft);
                    t = (0:N-1) / app.AudioFs;
                    
                    subplot(3, 2, i*2-1);
                    plot(t, filteredLeft);
                    title(sprintf('滤波后左声道 (SNR=%ddB)', snr));
                    xlabel('Time (s)');
                    ylabel('Amplitude');
                    grid on;
                    
                    subplot(3, 2, i*2);
                    plot(t, filteredRight);
                    title(sprintf('滤波后右声道 (SNR=%ddB)', snr));
                    xlabel('Time (s)');
                    ylabel('Amplitude');
                    grid on;
                end
                
                d.Value = 0.95;
                d.Message = '添加标题...';
                if d.CancelRequested, close(d); return; end
                
                sgtitle('不同SNR下的低通滤波输出对比');
                
                d.Value = 1;
                d.Message = '完成！';
                close(d);
                
            catch ME
                close(d);
                if ~contains(ME.message, 'Cancel')
                    uialert(app.UIFigure, ['绘制过程中出错: ' ME.message], '错误', 'Icon', 'error');
                end
            end
            
        end

        % Button pushed function: PlotBERCurveBtn
        function PlotBERCurveBtnPushed(app, event)
                
             if ~app.IsProcessingComplete
                uialert(app.UIFigure, '请先完成音频处理！', '错误', 'Icon', 'error');
                return;
            end
            
            % 简单的进度提示
            d = uiprogressdlg(app.UIFigure, 'Title', '正在绘制误码率曲线...', 'Message', '绘制中...', 'Cancelable', true);
            
            try
                d.Value = 0.3;
                if d.CancelRequested, close(d); return; end
                
                % 创建新图窗显示误码率曲线
                figure('Name', '误码率随信噪比变化曲线', 'Position', [350, 100, 800, 600]);
                
                d.Value = 0.7;
                d.Message = '绘制曲线...';
                if d.CancelRequested, close(d); return; end
                
                % 绘制所有信噪比的误码率曲线
                semilogy(app.SNRValues, app.BERLeftData, 'b*-', 'LineWidth', 1.5, 'MarkerSize', 8);
                hold on;
                semilogy(app.SNRValues, app.BERRightData, 'ro-', 'LineWidth', 1.5, 'MarkerSize', 8);
                grid on;
                xlabel('信噪比 (dB)');
                ylabel('误码率');
                title('误码率随信噪比变化曲线');
                legend('左声道: 8位A律13折线法编码', '右声道: 11位均匀量化编码', 'Location', 'best');
                xlim([min(app.SNRValues)-2, max(app.SNRValues)+2]);
                
                % 添加网格和数据标注
                for i = 1:length(app.SNRValues)
                    text(app.SNRValues(i), app.BERLeftData(i), sprintf(' %.2e', app.BERLeftData(i)), ...
                        'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'left', 'FontSize', 8, 'Color', 'blue');
                    text(app.SNRValues(i), app.BERRightData(i), sprintf(' %.2e', app.BERRightData(i)), ...
                        'VerticalAlignment', 'top', 'HorizontalAlignment', 'left', 'FontSize', 8, 'Color', 'red');
                end
                
                hold off;
                
                d.Value = 1;
                d.Message = '完成！';
                close(d);
                
            catch ME
                close(d);
                if ~contains(ME.message, 'Cancel')
                    uialert(app.UIFigure, ['绘制过程中出错: ' ME.message], '错误', 'Icon', 'error');
                end
            end
        
            
        end
    end

    % Component initialization
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)

            % Create UIFigure and hide until all components are created
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100 100 1291 750];
            app.UIFigure.Name = 'Design and Performance Analysis of PCM Audio Coding Transmission System';

            % Create ImportAudioMenu
            app.ImportAudioMenu = uimenu(app.UIFigure);
            app.ImportAudioMenu.MenuSelectedFcn = createCallbackFcn(app, @ImportAudioMenuSelected, true);
            app.ImportAudioMenu.Text = '导入音频文件';

            % Create TimeDomainAxes
            app.TimeDomainAxes = uiaxes(app.UIFigure);
            title(app.TimeDomainAxes, '采样后的初始音频时域图')
            xlabel(app.TimeDomainAxes, 'X')
            ylabel(app.TimeDomainAxes, 'Y')
            zlabel(app.TimeDomainAxes, 'Z')
            app.TimeDomainAxes.FontName = '楷体';
            app.TimeDomainAxes.FontSize = 18;
            app.TimeDomainAxes.Position = [603 425 652 298];

            % Create FrequencyDomainAxes
            app.FrequencyDomainAxes = uiaxes(app.UIFigure);
            title(app.FrequencyDomainAxes, '采样后的初始音频频域图')
            xlabel(app.FrequencyDomainAxes, 'X')
            ylabel(app.FrequencyDomainAxes, 'Y')
            zlabel(app.FrequencyDomainAxes, 'Z')
            app.FrequencyDomainAxes.FontName = '楷体';
            app.FrequencyDomainAxes.FontSize = 18;
            app.FrequencyDomainAxes.Position = [603 72 652 285];

            % Create Label
            app.Label = uilabel(app.UIFigure);
            app.Label.HorizontalAlignment = 'right';
            app.Label.FontName = '楷体';
            app.Label.FontSize = 24;
            app.Label.Position = [11 691 149 32];
            app.Label.Text = '音频文件路径';

            % Create AudioFilePathEdit
            app.AudioFilePathEdit = uieditfield(app.UIFigure, 'text');
            app.AudioFilePathEdit.Position = [175 691 286 32];

            % Create Label_2
            app.Label_2 = uilabel(app.UIFigure);
            app.Label_2.HorizontalAlignment = 'right';
            app.Label_2.FontName = '楷体';
            app.Label_2.FontSize = 24;
            app.Label_2.Position = [13 603 222 32];
            app.Label_2.Text = '显示的信噪比组选择';

            % Create SNRGroupDropdown
            app.SNRGroupDropdown = uidropdown(app.UIFigure);
            app.SNRGroupDropdown.Items = {'[19,15,-6]', '[19,12,-6]', '[19,9,-6]', '[19,6,-6]'};
            app.SNRGroupDropdown.FontName = 'Times New Roman';
            app.SNRGroupDropdown.FontSize = 24;
            app.SNRGroupDropdown.Position = [250 603 211 32];
            app.SNRGroupDropdown.Value = '[19,12,-6]';

            % Create PlotNoiseComparisonBtn
            app.PlotNoiseComparisonBtn = uibutton(app.UIFigure, 'push');
            app.PlotNoiseComparisonBtn.ButtonPushedFcn = createCallbackFcn(app, @PlotNoiseComparisonBtnPushed, true);
            app.PlotNoiseComparisonBtn.FontName = '楷体';
            app.PlotNoiseComparisonBtn.FontSize = 36;
            app.PlotNoiseComparisonBtn.Position = [11 333 450 57];
            app.PlotNoiseComparisonBtn.Text = '绘制加噪前后对比图';

            % Create PlotQuantizedSignalBtn
            app.PlotQuantizedSignalBtn = uibutton(app.UIFigure, 'push');
            app.PlotQuantizedSignalBtn.ButtonPushedFcn = createCallbackFcn(app, @PlotQuantizedSignalBtnPushed, true);
            app.PlotQuantizedSignalBtn.FontName = '楷体';
            app.PlotQuantizedSignalBtn.FontSize = 36;
            app.PlotQuantizedSignalBtn.Position = [11 425 450 57];
            app.PlotQuantizedSignalBtn.Text = '绘制量化后的时域图';

            % Create PlotEyeDiagramBtn
            app.PlotEyeDiagramBtn = uibutton(app.UIFigure, 'push');
            app.PlotEyeDiagramBtn.ButtonPushedFcn = createCallbackFcn(app, @PlotEyeDiagramBtnPushed, true);
            app.PlotEyeDiagramBtn.FontName = '楷体';
            app.PlotEyeDiagramBtn.FontSize = 36;
            app.PlotEyeDiagramBtn.Position = [11 238 450 57];
            app.PlotEyeDiagramBtn.Text = '绘制眼图';

            % Create PlotFilteredOutputBtn
            app.PlotFilteredOutputBtn = uibutton(app.UIFigure, 'push');
            app.PlotFilteredOutputBtn.ButtonPushedFcn = createCallbackFcn(app, @PlotFilteredOutputBtnPushed, true);
            app.PlotFilteredOutputBtn.FontName = '楷体';
            app.PlotFilteredOutputBtn.FontSize = 36;
            app.PlotFilteredOutputBtn.Position = [11 145 450 57];
            app.PlotFilteredOutputBtn.Text = '绘制低通滤波后的输出对比';

            % Create PlotBERCurveBtn
            app.PlotBERCurveBtn = uibutton(app.UIFigure, 'push');
            app.PlotBERCurveBtn.ButtonPushedFcn = createCallbackFcn(app, @PlotBERCurveBtnPushed, true);
            app.PlotBERCurveBtn.FontName = '楷体';
            app.PlotBERCurveBtn.FontSize = 36;
            app.PlotBERCurveBtn.Position = [11 46 450 57];
            app.PlotBERCurveBtn.Text = '绘制误码率曲线';

            % Create StartSamplingBtn
            app.StartSamplingBtn = uibutton(app.UIFigure, 'push');
            app.StartSamplingBtn.ButtonPushedFcn = createCallbackFcn(app, @StartSamplingBtnPushed, true);
            app.StartSamplingBtn.FontName = '楷体';
            app.StartSamplingBtn.FontSize = 18;
            app.StartSamplingBtn.Position = [477 692 100 31];
            app.StartSamplingBtn.Text = '开始采样';

            % Create StartProcessingBtn
            app.StartProcessingBtn = uibutton(app.UIFigure, 'push');
            app.StartProcessingBtn.ButtonPushedFcn = createCallbackFcn(app, @StartProcessingBtnPushed, true);
            app.StartProcessingBtn.FontName = '楷体';
            app.StartProcessingBtn.FontSize = 36;
            app.StartProcessingBtn.Position = [12 519 450 57];
            app.StartProcessingBtn.Text = '开始处理';

            % Show the figure after all components are created
            app.UIFigure.Visible = 'on';
        end
    end

    % App creation and deletion
    methods (Access = public)

        % Construct app
        function app = PCM_App

            % Create UIFigure and components
            createComponents(app)

            % Register the app with App Designer
            registerApp(app, app.UIFigure)

            if nargout == 0
                clear app
            end
        end

        % Code that executes before app deletion
        function delete(app)

            % Delete UIFigure when app is deleted
            delete(app.UIFigure)
        end
    end
end