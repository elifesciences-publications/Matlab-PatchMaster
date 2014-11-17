% AnalyzePatchData.m

%% Import Data

% Don't forget to run sigTOOL first!
ephysData = ImportPatchData();

%% Filter data by project
% Specify project name(s) to keep in cell array of strings. Toss out other 
% crap recordings or unidentified cells that will not be analyzed.
projects = {'FAT'};
dataFields = fieldnames(ephysData);
validProject = zeros(length(dataFields),1);

for iProj = 1:length(projects)
    isValid = strncmpi(dataFields,projects{iProj},length(projects{iProj}));
    validProject = validProject + isValid;
end

ephysData = rmfield(ephysData,dataFields(~logical(validProject)));

clearvars -except ephysData

%% Analyze capacity transient
allCells = fieldnames(ephysData);

for iCell = 1:length(allCells)
cellName = allCells{iCell}; %split into project name and cell numbers when feeding input

% UPDATE: after June/July 2014 (FAT025), Patchmaster has separate pgfs for 
% 'OC_ct_neg' and 'WC_ct_neg' to make it easier to pull out only capacity 
% transients of interest without having to check the notebook.
protName = 'ct_neg';
% two alternatives for finding instances of the desired protocol
% find(~cellfun('isempty',strfind(ephysData.(cellName).protocols,'ct_neg')));
protLoc = find(strncmp(protName,ephysData.(cellName).protocols,6));

Ct = zeros(1,length(protLoc));
tau = zeros(1,length(protLoc));
Rs = zeros(1,length(protLoc));

% TO DO: fliplr for matching longer names ending in "ct_neg".
protName = 'WC_ct_neg';
% two alternatives for finding instances of the desired protocol
% find(~cellfun('isempty',strfind(ephysData.(cellName).protocols,'ct_neg')));
protLoc = find(strncmp(protName,ephysData.(cellName).protocols,9));

for i = 1:length(protLoc)
%     figure(); hold on;
    
    % Pull out capacity transient data, subtract leak at holding, multiply
    % the negative by -1 to overlay it on the positive, then plot, and 
    % combine the two for the mean (visual check yourself if they really 
    % are equivalent)
    ctNeg = -1.*ephysData.(cellName).data{1,protLoc(i)};
    ctPos = ephysData.(cellName).data{1,protLoc(i)+1};

    ctNeg = bsxfun(@minus, ctNeg, mean(ctNeg(1:20,:)));
    ctPos = bsxfun(@minus, ctPos, mean(ctPos(1:20,:)));

    meanCt = mean([ctNeg ctPos],2);
%     plot(mean(ctNeg,2),'b')
%     plot(mean(ctPos,2),'r')
%     plot(meanCt,'k')
    
    deltaV = 10E-3; % V, 10 mV step
    
    % current during last 10 points of voltage step, dependent on series
    % resistance + leak
    IRsLeak = mean(meanCt(140:149));
    
    % current due to Rs + leak resistance for given deltaV, will be 
    % subtracted from total current to get capacitance current
    rsLeakSub = deltaV/IRsLeak;   % estimate of series resistance, for comparison
    ICt = meanCt-IRsLeak;
%     plot(ICt,'g')

    % TODO: IMPORT SAMPLING FREQUENCY from metadata tree
    % Find the peak capacitative current, then find the point where it's
    % closest to zero, and calculate the area in between.
    % TODO: Change intStart to first zero crossing following t=50
    intStart = 52;
    intEnd = find(abs(ICt) == min(abs(ICt(intStart:150))));
    % trapz uses the trapezoidal method to integrate & calculate area under
    % the curve. But it assumes unit spacing, so divide by the sampling
    % frequency (10kHz in this case) to get units of seconds.
    intICt = trapz(ICt(intStart:intEnd))/10000;  
    % Calculate capacitance based on I = C*(dV/dt)
    Ct(i) = intICt/deltaV;

    % For fitting the curve to find the decay time constant, use peak cap 
    % current as the start point, and fit the next 2ms. This finds an
    % equation of the form Y=a*e^(bx), which is V(t) = Vmax*e^(-t/tau). So
    % the time constant tau is -1/capFit.b .
  
    % TODO: Try picking the end time as the time when it decays to 1/2e, to
    % make sure you have enough points to fit the fast component if it does
    % turn out to be a double exponential. Else, fit a shorter time than
    % 5ms. Either way, stick with exp1 because it's simpler (and because
    % you're focusing on the fast component). Compare the two.
    
    sampFreq = 1E4; % Hz
    fitStart = find(ICt == max(ICt(45:60)));  
    [~,fitInd] = min(abs(ICt(fitStart:150)-(ICt(fitStart)/(2*exp(1)))));
    
    fitTime = fitInd/sampFreq; % seconds
    t = 0:1/sampFreq:fitTime; % UPDATE with sampling frequency
    
    capFit = fit(t',ICt(fitStart:fitStart+fitInd),'exp1');
%     plot(capFit,t,ICt(intStart:intStart+minInd));
    
    % Calculate time constant in seconds.
    tau(i) = -1/capFit.b;
    % Calculate series resistance from tau = Rs*Cm, and divide by 1E6 for
    % units of megaohms.
    Rs(i) = tau(i)/Ct(i)/1E6;
end

ephysData.(cellName).Ct = Ct;
ephysData.(cellName).tau = tau;
ephysData.(cellName).Rs = Rs;

end

clearvars -except ephysData;

%% Display all series resistances for testing
for iCell = 1:length(allCells)
ephysData.(allCells{iCell}).Rs
end

%% Look at current clamp
allCells = fieldnames(ephysData);

for iCell = 1:length(allCells)
    cellName = allCells{iCell}; %split into project name and cell numbers when feeding input
    
    % UPDATE: after June/July 2014 (FAT025), Patchmaster has separate pgfs for
    % 'OC_ct_neg' and 'WC_ct_neg' to make it easier to pull out only capacity
    % transients of interest without having to check the notebook.
    protName = 'cc_gapfree';
    % two alternatives for finding instances of the desired protocol
    % find(~cellfun('isempty',strfind(ephysData.(cellName).protocols,'ct_neg')));
    protLoc = find(strncmp(protName,ephysData.(cellName).protocols,6));
    
    if protLoc
        for i = 1:length(protLoc)
            gapfree(:,i) = ephysData.(cellName).data{1,protLoc(i)};
        end
        basalVoltage{iCell} = gapfree;
    end
end

%% Plot current steps

allCells = {'FAT017';'FAT020';'FAT021';'FAT028'};


for iCell = 1:length(allCells)
    cellName = allCells{iCell}; %split into project name and cell numbers when feeding input
    
    % UPDATE: after June/July 2014 (FAT025), Patchmaster has separate pgfs for
    % 'OC_ct_neg' and 'WC_ct_neg' to make it easier to pull out only capacity
    % transients of interest without having to check the notebook.
    protName = 'IVq';
    % Flip protName and actual protocol names to compare the last 3 letters
    % when looking for IVq, to get all IVqs without regard to OC vs. WC.
    flippedProts = cellfun(@fliplr, ephysData.(cellName).protocols, ...
        'UniformOutput', false);
    
    % two alternatives for finding instances of the desired protocol
    % find(~cellfun('isempty',strfind(ephysData.(cellName).protocols,'ct_neg')));
    protLoc = find(strncmp(fliplr(protName),flippedProts,3));
    
    if protLoc
        for i = 1:length(protLoc)
            ivq{i} = ephysData.(cellName).data{1,protLoc(i)};
        end
        ivSteps{iCell} = ivq;
    end
end

dt = 0.2; % ms
tVec = 0:dt:210-dt;

clear iCell cellName protName flippedProts protLoc i

FAT020_OC = ivSteps{2}(1:3);
FAT020_OC_mean = mean(reshape(cell2mat(FAT020_OC),[1050 12 3]),3);
FAT020_WC = ivSteps{2}(4:6);
FAT020_WC_mean = mean(reshape(cell2mat(FAT020_WC),[1050 12 3]),3);

plot(tVec, (FAT020_WC_mean-FAT020_OC_mean)/1E-12, 'b')

figure()
FAT021_OC = ivSteps{3}(1:3);
FAT021_OC_mean = mean(reshape(cell2mat(FAT021_OC),[1050 12 3]),3);
FAT021_WC = ivSteps{3}(4:6);
FAT021_WC_mean = mean(reshape(cell2mat(FAT021_WC),[1050 12 3]),3);

plot(tVec, (FAT021_WC_mean-FAT021_OC_mean)/1E-12, 'b')

% figure()
% FAT024_OC = ivSteps{4}(1:3);
% FAT024_OC_mean = mean(reshape(cell2mat(FAT024_OC),[1050 12 3]),3);
% FAT024_WC = ivSteps{4}(7:9);
% FAT024_WC_mean = mean(reshape(cell2mat(FAT024_WC),[1050 12 3]),3);
% 
% plot(tVec, (FAT024_WC_mean-FAT024_OC_mean)/1E-12, 'b')

figure()
FAT028_OC = ivSteps{4}(1:3);
FAT028_OC_mean = mean(reshape(cell2mat(FAT028_OC),[1050 12 3]),3);
FAT028_WC = ivSteps{4}(10:12);
FAT028_WC_mean = mean(reshape(cell2mat(FAT028_WC),[1050 12 3]),3);

plot(tVec, (FAT028_WC_mean-FAT028_OC_mean)/1E-12, 'b')


%% Plot mechanically evoked currents

probeI = ephysData.FAT028.data{1,22};
nSteps = size(probeI,2);

% Timepoint in sweep at which probe starts pushing (on) and when it goes
% back to neutral position (off).
% LATER: Make these variables that can be fed in for timing protocols.
onPoint = 1000;
offPoint = 6000;

mechPeaks = zeros(size(probeI,2)-2,2);

for i = 1:nSteps-2
    % Get baseline for each step by grabbing the mean of the 250ms before
    % the probe displacement.
    baseProbeI_on = mean(probeI(onPoint-251:onPoint-1,i));
    baseProbeI_off = mean(probeI(offPoint-251:offPoint-1,i));
    
    % Find the peak current for the on step and the off step for this sweep
    onSubtract = probeI(:,i) - baseProbeI_on;
    peakOnLoc = find(abs(onSubtract(onPoint:onPoint+500)) == max(abs(onSubtract(onPoint:onPoint+500))));
    peakOnLoc = peakOnLoc(1) + onPoint;
    
    offSubtract = probeI(:,i) - baseProbeI_off;
    peakOffLoc = find(abs(onSubtract(onPoint:onPoint+500)) == max(abs(onSubtract(onPoint:onPoint+500))));
    peakOffLoc = peakOffLoc(1)+offPoint;
    
    mechPeaks(i,1) = onSubtract(peakOnLoc);
    mechPeaks(i,2) = offSubtract(peakOffLoc);
    
    % TO DO: Fit the current with exp1 and calculate tau
end




figure()
hold on;
plot(0:8,mechPeaks(:,1)/1E-12,'b')
plot(0:8,mechPeaks(:,2)/1E-12,'r')
set(gca,'YDir','reverse');
plotfixer;

dt = 0.001; % s
tVec = 0:dt:7-dt;

figure()
plot(tVec, probeI(:,1)/1E-12)
figure()
plot(tVec, probeI(:,5)/1E-12)
figure()
plot(tVec, probeI(:,9)/1E-12)
