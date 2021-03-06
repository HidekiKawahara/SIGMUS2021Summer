%%   Fujisaki-Sagayama pitch checker
%    and vocal tract shape visualizer
%    with interactive spectrum tilt manipulation

%    Copyright (c) by Hideki Kawahara 2021

aaa = audiodevinfo;
nAudioIn = audiodevinfo(1);
names = cell(nAudioIn,1);
idList = zeros(nAudioIn,1);
outnames = cell(nAudioIn,1);
outidList = zeros(nAudioIn,1);
for ii = 1:nAudioIn
    names(ii) = {aaa.input(ii).Name};
    idList(ii) = aaa.input(ii).ID;
    outnames(ii) = {aaa.output(ii).Name};
    outidList(ii) = aaa.output(ii).ID;
end
%%
%aaa = foViewer;
CntrlStr = fsController;
[idx, tf] = listdlg('ListString', names, 'ListSize', [300, 200] ...
    ,'Name', 'Select input device', 'SelectionMode','single');
if ~tf
    disp('Device assignment is cancelled!');
    return;
end
recorderID = idList(idx);
%%
fs = 8000;
fL = 55;
fH = 2000;
fftl = 2048;
fx = (0:fftl-1)'/fftl*fs;
fcList = fL * 2 .^ (0:1/12:log2(fH/fL))';
specWeight = zeros(length(fcList), fftl/2);
for ii = 1:length(fcList)
    normFx = fx(fx<fcList(ii) * 2) - fcList(ii);
    normFx = max(-1, min(1,1.3*normFx / fcList(ii)));
    specWeight(ii, fx<fcList(ii) * 2) = ...
        0.5 + 0.5 * cos(pi * normFx)';
    specWeight(ii, fx<fcList(ii) * 2) = specWeight(ii, fx<fcList(ii) * 2) ...
        / sqrt(sum(specWeight(ii, fx<fcList(ii) * 2)));
end
recorder = audiorecorder(fs,24,1,recorderID);
%set(recorder, 'TimerPeriod', 0.02);
currentTime = now;
testDuration = 20;
testPeriod = 0.05;
checkResolution = 0.03; % 30ms
durationStat = zeros(round(testDuration / 0.05) + 10, 10);
blankTime = zeros(10, 2);
baseTic = tic;
%---- layout base
foFigure = figure;
set(gcf,'position', [200          77        1161         900], ...
    'BusyAction',"cancel")
tlayout = tiledlayout(6,6); % tiledlayout(nRow,nColumn)
tlayout.TileSpacing = 'compact';
tt = ((1:fftl)' - fftl/2)/fs*1000;

%--- wave monitor
%subplot(234)
waveAxis = nexttile(tlayout, 3, [2, 2]);
waveHandle = plot(tt, rand(fftl,1));grid on;
axis([tt(1) tt(end) -1 1]);
fx = (0:fftl-1)'/fftl*fs;
nx = ((1:fftl)' - fftl/2 -1 )/fftl*2;
w = exp(-(6*nx).^2);
hold on
plot(tt, w, 'g', 'linewidth', 3);
plot(tt, -w, 'g', 'linewidth', 3);
xlabel('time (ms)');

%--- spectrum monitor
%subplot(231);
specAxis = nexttile(tlayout, 5, [2, 2]);
specHandle = plot(fx, 20*log10(abs(fft(rand(fftl,1).*w))));grid on;
%titleHandle = title(num2str(testDuration));
hold all
specSmoothHandle = plot(fx, 20*log10(abs(fft(rand(fftl,1).*w))),'linewidth', 2);
envLPCHandle = plot(fx, 20*log10(abs(fft(rand(fftl,1).*w))),'g','linewidth', 2, ...
    'color', [0 0.7 0]);
baseSegment = (1:fftl)' - fftl;
axis([0 fs/2 -80 40]);
xlabel('frequency (Hz)');
ylabel('level (rel. dB)');
title('LPC envelope is 6cB raised');

%--- inst. freq. monitor
%subplot(232);
ifAxis = nexttile(tlayout, 1, [2, 2]);
ifHandle = loglog(fcList, fcList);grid on;
hold all
ifTgtIndHandle = loglog([0 0] + 110, [fL fH], '-', 'linewidth', 3, 'color', [1 0.5 0.5]);
ifIndHandle = loglog([0 0] + fL, [fL fH], 'g', 'linewidth', 3);
axis([40 fH fL fH]);
loglog([fL fH], [fL fH], 'k');
fixpHandle = loglog(fcList, fcList, 'or', 'linewidth', 2);
hold off
xlabel('frequency (Hz)');
ylabel('inst. frequency (Hz)');
%foStrHandle = title(num2str(fL, '%7.1f') + " (Hz)");

%--- AM FM monitor
%subplot(235)
amfmAxis = nexttile(tlayout, 13,  [2, 2]);
mixHandle = loglog(fcList, fcList *0 + 0.01);grid on;
hold all
amfmTgtIndHandle = loglog([0 0] + 110, [10^(-8) 0.005], '-', 'linewidth', 3, 'color', [1 0.5 0.5]);
chIndHandle = loglog([0 0] + fL, [10^(-8) 0.005], 'g-', 'linewidth', 3);
axis([40 fH 10^(-8) 0.001]);
hold off
xlabel('frequency (Hz)');
ylabel('AM and FM deviation');

linkaxes([ifAxis,amfmAxis],'x');

%--- for FjSg plot preparation
wfs = zeros(fftl, 6);
nxfs = ((1:fftl)' - fftl/2 -1 )/fftl;
for ii = 1:6
    nxfs = nxfs * 2;
    wfs(abs(nxfs) < 1, ii) = exp(-(6*nxfs(abs(nxfs) < 1)).^2);
end

mresSpec = zeros(fftl, 6);
modAc = zeros(fftl, 6);
modAcH = zeros(fftl, 6);
meanAc = zeros(fftl, 1);
meanAcH = zeros(fftl, 1);
ySpec = zeros(fftl, 8);
fxBi = fx;
fxBi(fx > fs/2) = fxBi(fx > fs/2) - fs;
freqByLag = 1 ./((0:fftl-1)'/fs);
th = fxBi/fs*2*pi;
betaa = 3;
wNormSpec = exp(betaa * cos(th))/exp(betaa);
muu = 2500/(fs/2)*pi;
wNormSpecH = exp(betaa * cos(th-muu))/exp(betaa);

%--- for FjSg plot
%subplot(233);
fjsgAxis = nexttile(tlayout, 25, [2, 2]);
fsAcHandle = semilogx(freqByLag, rand(fftl, 1) -0.1);grid on;
hold all
fsAcHHandle = semilogx(freqByLag, rand(fftl, 1) -0.1);grid on;
fJsGTgtIndHandle = semilogx([0 0] + 110, [-1 1], '-', 'linewidth', 3, 'color', [1 0.5 0.5]);
xlabel('frequency (Hz)');
ylabel('modified autocorrelation');
axis([20 fH/2 -1 1])
hold off

%--- Information display
infoAxis = nexttile(tlayout, 15,[2, 1]);
axis([0 6 0 6]);
text(1, 5, 'Time left (s)');
secLeftHandle = text(1, 4, num2str(20, '%6.2f'), 'fontsize', 20);
text(1, 3, 'Fund. Freq. (Hz)');
foValueHandle = text(1, 2, num2str(110, '%7.1f'), 'fontsize', 20);
axis off

%---- vocal tract shape display
vtShapeAxis = nexttile(tlayout, 22,[3, 3]);
crossSection =  [0.2803; ...
    0.6663; ...
    0.5118; ...
    0.3167; ...
    0.1759; ...
    0.1534; ...
    0.1565; ...
    0.1519; ...
    0.0878; ...
    0.0737];
[X,Y,Z] = cylinder(crossSection,40);
tract3DHandle = surf(Z,Y,X);
view(-26,12);
axis([0 1 -1 1 -1 1]);
axis off;
axis('vis3d');
rotate3d on;
logAreaAxis = nexttile(tlayout, 16,[1, 3]);
areaIdx = floor(1:1/2:10.6);
locIdx = floor((1:1/2:10.6) - 1/2);
logAreaT = log(crossSection(areaIdx));
logAreaT = (logAreaT - min(logAreaT)) / (max(logAreaT) - min(logAreaT));
logAreaHandle = plot(locIdx, logAreaT,'k', 'linewidth', 2);
axis([0 locIdx(end) 0 1]);
axis off;

%%
freqByLag = 1 ./((0:fftl-1)'/fs);
freqByLag(isnan(freqByLag)) = fs*fs;
wLag = zeros(fftl, 6);
fcwList = [50 100 200 400 800 1600];
for ii = 1:6
    nlx = freqByLag(fcwList(ii)/2 < freqByLag & freqByLag < fcwList(ii)*2);
    nlxLog = log2(nlx / fcwList(ii));
    wLag(fcwList(ii)/2 < freqByLag & freqByLag < fcwList(ii)*2, ii) = ...
        0.5 + 0.5 * cos(pi * nlxLog);
end
wLag(freqByLag > fL/3 & freqByLag < fcwList(1) , 1) = 1;
wLag(freqByLag < fH * 1.3 & freqByLag > fcwList(6) , 6) = 1;
wLag(freqByLag >= fH * 1.3  , 6) = 0;

%%
idxx = (1:length(fcList));
smsPylamid = zeros(fftl, 6);
s = crossSection * 0;
n = length(s) - 1;
while get(CntrlStr.TargetfoEditField, 'Value') ~= 0
    record(recorder);
    while get(recorder, 'CurrentSample') < 10
        pause(checkResolution);
    end
    countID = 0;
    startTic = tic;
    nextTime = fftl/fs;
    targetTime = testDuration;
    startEnd = zeros(round(testDuration / 0.05) + 10, 3);
    while targetTime > toc(startTic)
        timeLeft = nextTime - toc(startTic);
        pause(nextTime - toc(startTic));
        y = getaudiodata(recorder);
        if timeLeft > 0.001
            countID = countID + 1;
            startEnd(countID, 1) = toc(startTic);
            for jj = 1:8
                ySpec(:, jj) = fft(fftshift(y(end + baseSegment + jj -8) .* w));
            end
            meanAc = meanAc*0;
            meanAcH = meanAc;
            for jj = 1:6
                mresSpec(:, jj) = fft(fftshift(y(end + baseSegment -4) .* wfs(:,jj)));
                pw = abs(mresSpec(:,jj)).^2;
                rr = ifft(pw,'symmetric');
                sms = ifft(rr .* fftshift(wfs(:,jj)), 'symmetric');
                smsPylamid(:, jj) = sms;
                fineStrSpec = pw ./ sms;
                modAc(:, jj) = ifft(wNormSpec .* (fineStrSpec - mean(fineStrSpec)), 'symmetric');
                meanAc = meanAc + modAc(:, jj) .* wLag(:,jj) / 210;
                modAcH(:, jj) = ifft(wNormSpecH .* (fineStrSpec - mean(fineStrSpec)));
                meanAcH = meanAcH + abs(modAcH(:, jj)) .* wLag(:,jj) / 210;
            end
            istSpec = specWeight * ySpec(1:fftl/2, :);
            istIfq = angle(istSpec(:,2:8)./istSpec(:,1:7))*fs/2/pi;
            meanIf = mean(istIfq,2);
            relIf = istIfq - fcList;
            meanReftIf = mean(relIf,2);
            fixPdata = fcList * NaN;
            fmDevTmp = std(diff(istIfq'))'./fcList;
            amDevTmp = std(diff(abs(istSpec)'))'./mean(abs(istSpec'))';
            mixDevTmp = amDevTmp ./(fcList) .^(1.5)/0.0146 + fmDevTmp./(fcList);
            fxp = [idxx(meanReftIf .* meanReftIf(max(1, idxx-1)) < 0 & meanReftIf < meanReftIf(max(1, idxx-1))), idxx(end)];
            fixpIf = (meanIf(fxp) - meanIf(fxp-1)) ./ (fcList(fxp) - fcList(fxp-1)) .* meanReftIf(fxp-1) + meanIf(fxp-1);
            fixPdata(1:length(fxp)) = fixpIf;
            [minDev, bestId] = min(mixDevTmp(fxp));
            estIf = fixpIf(bestId);
            set(waveHandle, 'ydata', y(end-fftl +1:end) / max(abs(y(end-fftl +1:end))));
            if CntrlStr.TargetfoEditField.Value == 0
                break;
            end
            switch CntrlStr.CommonInfo.foUseMode
                case 'Manual'
                    tmpChId = min(length(fcList) - 1, 1 + log2(CntrlStr.TargetfoEditField.Value/fL));
                case 'Auto'
                    if minDev < 10^(-5)
                        tmpChId = min(length(fcList) - 1, 1 + log2(2.4*estIf/fL));
                    else
                        tmpChId = min(length(fcList) - 1, 1 + log2(CntrlStr.TargetfoEditField.Value/fL));
                    end
            end
            %tmpChId = min(length(fcList) - 1, 1 + log2(CntrlStr.TargetfoEditField.Value/fL));
            chIdBase = min(5, floor(tmpChId));
            chIdFrac = min(1, tmpChId - chIdBase);
            msPw = (1-chIdFrac) * smsPylamid(:, chIdBase) + chIdFrac*smsPylamid(:, chIdBase + 1);
            rawPw = abs(fft(y(end-fftl +1:end).*w)) .^2;
            msPw = msPw / sum(msPw) * sum(rawPw);
            msAc = ifft(msPw .* CntrlStr.CommonInfo.gain, 'symmetric');
            [alp, err, k] = levinson(msAc, 12);
            tmpLPCenv = 1./(abs(fft(alp, fftl)) .^2);
            envLPCpwdB = 6+10*log10(tmpLPCenv / sum(tmpLPCenv) * sum(rawPw .* CntrlStr.CommonInfo.gain));
            %n = length(k);
            kn = -k;
            %s = zeros(n+1,1);
            s(end) = 1;
            for ii = n:-1:1
                s(ii) = s(ii+1)*(1-kn(ii))/(1+kn(ii));
            end
            %tmpCrossSctn = sqrt(s/sum(s));
            [X,Y,Z] = cylinder(sqrt(s/sum(s)),40);
            set(tract3DHandle,'xdata',Z,'ydata',Y,'zdata',X);
            logAreaT = log(s(areaIdx));
            logAreaT = (logAreaT - min(logAreaT)) / (max(logAreaT) - min(logAreaT));
            set(logAreaHandle, 'ydata', logAreaT);
            set(specHandle, 'ydata', 10*log10(rawPw) + CntrlStr.CommonInfo.gainIndB);
            set(specSmoothHandle, 'ydata', 10*log10(msPw) + CntrlStr.CommonInfo.gainIndB);
            set(envLPCHandle, 'ydata', envLPCpwdB);
            set(ifHandle, 'ydata', mean(istIfq,2));
            set(mixHandle, 'ydata', mixDevTmp);
            set(fixpHandle, 'xdata', fixPdata, 'ydata', fixPdata);
            set(fsAcHandle, 'ydata', meanAc);
            set(fsAcHHandle, 'ydata', meanAcH);
            [~, bestCh] = min(mixDevTmp);
            set(chIndHandle, 'xdata', [0 0] + estIf);
            set(ifIndHandle, 'xdata', [0 0] + estIf);
            set(ifTgtIndHandle, 'xdata', [0 0] + CntrlStr.TargetfoEditField.Value);
            set(amfmTgtIndHandle, 'xdata', [0 0] + CntrlStr.TargetfoEditField.Value);
            set(fJsGTgtIndHandle, 'xdata', [0 0] + CntrlStr.TargetfoEditField.Value);
            set(foValueHandle, 'String', num2str(mean(istIfq(bestCh,:)), '%7.1f') + " (Hz)");
            set(secLeftHandle, 'String', num2str(testDuration - nextTime, '%6.2f'));
            drawnow limitrate
        end
        if get(CntrlStr.TargetfoEditField, 'Value') == 0
            break
        end
        nextTime = nextTime + testPeriod;
    end
    set(secLeftHandle, 'String', num2str(0));
    stop(recorder);
end
close(CntrlStr.UIFigure)
pause(0.5)
close(foFigure)