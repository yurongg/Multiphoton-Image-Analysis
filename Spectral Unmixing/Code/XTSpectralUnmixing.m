%
%
%  K-means Spectral Clustering Function for Imaris 
%
%  Tristan McRae 2018
%  References - http://www.scs2.net/next/files/courses/iic/ImarisOpenLaunchExtract.pdf
%
%  Installation:
%
%  - Copy this file into the XTensions folder in the Imaris installation directory
%  - You will find this function in the Image Processing menu
%
%    <CustomTools>
%      <Menu>
%        <Submenu name="Custom Extensions">
%          <Item name="Spectral Unmixing" icon="Matlab" tooltip="Split overlapping fluorophores to each have their own channel">
%            <Command>MatlabXT::XTSpectralUnmixing(%i)</Command>
%          </Item>
%        </Submenu>
%      </Menu>
%    </CustomTools>
%  
%
%  Description:
%
%   This XTension separates pixels into clusters based on their spectral
%   signatures
%   This helps to discriminate between pixels that share a dominant
%   channel but belong to different parts of the cell
%
%



function XTSpectralUnmixing(aImarisApplicationID)

%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%Load data
%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ID
disp('Loading data into MATLAB (for large datasets, this may take some time)')

disp('Setting up connection')
% Set up connection	between	Imaris and MATLAB
if	isa(aImarisApplicationID, 'Imaris.IApplicationPrxHelper')
    vImarisApplication = aImarisApplicationID;
else
    % connect to Imaris interface
    javaaddpath ImarisLib.jar
    vImarisLib = ImarisLib;
    if	ischar(aImarisApplicationID)
        aImarisApplicationID = round(str2double(aImarisApplicationID));
    end
    vImarisApplication = vImarisLib.GetApplication(aImarisApplicationID);
end

%Set up progress bar
vProgressDisplay = waitbar(0,'Spectral Unmixing:Loading Data...');

disp('Finding the dataset properties')
% Get the vDataSet object
vDataSet = vImarisApplication.GetDataSet();
% Get the data type
switch char(vDataSet.GetType())
    case 'eTypeUInt8', datatype = 'uint8';
    case 'eTypeUInt16', datatype = 'uint16';
    case 'eTypeFloat', datatype = 'single';
    otherwise, error('Bad value for vDataSet.GetType()');
end
% Allocate memory
disp('Allocating Memory')
x_dim = vDataSet.GetSizeX();
y_dim = vDataSet.GetSizeY();
z_dim = vDataSet.GetSizeZ();
num_channels = vDataSet.GetSizeC();
num_timesteps = vDataSet.GetSizeT();

stack = zeros([x_dim, y_dim, z_dim, num_channels, num_timesteps], datatype);
basic_stack = zeros([x_dim, y_dim, z_dim], datatype);
% Get the pixel data
for t = 1:num_timesteps
    waitbar(0.1*t/num_timesteps);
    disp(strcat("Reading timestep ", int2str(t), " of ", int2str(num_timesteps)))
    pause(0.01) %let the display catch up
    for c = 1:num_channels
        switch char(vDataSet.GetType())
            case 'eTypeUInt8'
                arr = vDataSet.GetDataVolumeAs1DArrayBytes(c-1, t-1); 
                basic_stack(:) = typecast(arr, 'uint8');
                stack(:, :, :, c, t) = basic_stack;
                
            case 'eTypeUInt16'
                arr	= vDataSet.GetDataVolumeAs1DArrayShorts(c-1, t-1);
                basic_stack(:) = typecast(arr, 'uint16');
                stack(:, :, :, c, t) = basic_stack;
                
            case 'eTypeFloat'
                basic_stack(:) = vDataSet.GetDataVolumeAs1DArrayFloats(c-1, t-1);
                stack(:, :, :, c, t) = basic_stack; 
            otherwise, error('Bad value for type');
        end
    end
end

%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

%for c = 1:num_channels
%    channel_names(c) = vDataSet.GetChannelName(c-1);
%end



[unmixed_image, infer_channel_names, extra_channel_names]  = spectral_unmixing_gui(num_channels, num_timesteps, x_dim, y_dim, z_dim, stack);
disp('returning image')
close all;
vProgressDisplay = waitbar(0.8,'Returning Image to Imaris');
return_results_to_imaris(unmixed_image, vDataSet, num_timesteps, vImarisApplication, infer_channel_names, extra_channel_names);

close all

end

%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%Prompt user for unmixing details
%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
function [unmixed_image, infer_channel_names, extra_channel_names] = spectral_unmixing_gui(num_channels, num_timesteps, x_dim, y_dim, z_dim, mixed_image)
    close all;

    h.f = figure('units','pixels','position',[700,500,150,100],...
                 'toolbar','none','menu','none', 'Name', 'Unmixing Method', 'NumberTitle', 'off');

    h.t = uicontrol('style', 'text','units', 'pixels',...
        'position',[0, 60, 150, 30], 'string', 'Select an unmixing method');           

    h.d = uicontrol('style', 'popupmenu', 'units', 'pixels',...
        'position',[10, 30, 90, 30], 'string', 'K-means|SIMI (coming soon!)|NNMF (coming soon!)');

    h.p = uicontrol('style','pushbutton','units','pixels',...
                    'position',[40,5,70,20],'string','OK',...
                    'callback',@d_call);
    uiwait(h.f)
    % Dropdown callback
    function d_call(varargin)
        vals = get(h.d,'Value');
        switch vals
            case 1
                [unmixed_image, infer_channel_names, extra_channel_names] = k_means_gui(num_channels, num_timesteps, x_dim, y_dim, z_dim, mixed_image); 
            case 2
                [unmixed_image, infer_channel_names, extra_channel_names] = simi_gui(mixed_image); 
            case 3
                [unmixed_image, infer_channel_names, extra_channel_names] = nnmf_gui(mixed_image); 

        end
        close all;
    end

end


function [unmixed_image, infer_channel_names, extra_channel_names] = k_means_gui(num_channels, num_timesteps, x_dim, y_dim, z_dim, mixed_image)
    height = 400;
    width = 500; %max(20+40*num_channels, 300)
    h.f = figure('units','pixels','position',[700,500,width,height],...
                 'toolbar','none','menu','none', 'Name', 'K-Means Settings', 'NumberTitle', 'off');

    h.t(1) = uicontrol('style', 'text','units', 'pixels',...
        'position',[5, height-40, 400, 30], 'string', 'How many fluorophores do you want to unmix? (Including background)');      

    h.num_fluorophores_to_unmix = uicontrol('style', 'edit','units', 'pixels',...
        'position',[50, height-60, 40, 30]);        

    h.t(2) = uicontrol('style', 'text','units', 'pixels',...
        'position',[0, height-100, 200, 30], 'string', 'Select which channels to unmix');

    for i = 1:num_channels
        h.c(i) = uicontrol('style','checkbox','units','pixels',...
                        'position',[40+40*(i-1),height-110,50,15],'string',int2str(i));
    end
    
    h.t(1) = uicontrol('style', 'text','units', 'pixels',...
        'position',[0, height-150, 400, 30], 'string', 'Number of Replicates (Runs k-means Multiple Times and Uses Best Result)');  
    
    h.replicates = uicontrol('style', 'edit','units', 'pixels',...
        'position',[50, height-170, 40, 30]); 
          
    h.t(2) = uicontrol('style', 'text','units', 'pixels',...
        'position',[-20, height-200, 300, 30], 'string', 'Representitive timestep to base clustering on');      

    h.representitive_timestep = uicontrol('style', 'edit','units', 'pixels',...
        'position',[50, height-220, 40, 30]); 
    
    h.t(3) = uicontrol('style', 'text','units', 'pixels',...
        'position',[20, height-260, 200, 30], 'string', 'Representitive slice to base clustering on');      

    h.representitive_slice = uicontrol('style', 'edit','units', 'pixels',...
        'position',[50, height-280, 40, 30]); 
    
    h.scale = uicontrol('style','checkbox','units','pixels',...
                        'position',[20,height-310,400,15],'string','Cluster Based on Ratio of Channels (Instead of Absolute Channel Values)');
                    
    h.multi_fluorophore = uicontrol('style','checkbox','units','pixels',...
                        'position',[20,height-330,400,15],'string','Allow multiple clusters to occupy a single channel');
    
    h.infer_channel_names = uicontrol('style','checkbox','units','pixels',...
                        'position',[20,height-350,400,15],'string','Infer Channel Names');
                    
                    
    h.p = uicontrol('style','pushbutton','units','pixels',...
                    'position',[40,5,70,20],'string','OK',...
                    'callback',@p_call);
    uiwait(h.f)

    function p_call(varargin)
        vals = get(h.c,'Value');
        if length(vals)>1
            channels_to_unmix = find([vals{:}]);
        else
            channels_to_unmix = find(vals);
        end
        num_fluorophores_to_unmix = str2num(get(h.num_fluorophores_to_unmix, 'String'));
        replicates = str2num(get(h.replicates, 'String'));
        scaled_signatures = get(h.scale,'Value');
        multi_fluorophore_pixels = get(h.multi_fluorophore,'Value');
        infer_channel_names = get(h.infer_channel_names,'Value');
        representitive_timestep = str2num(get(h.representitive_timestep, 'String'));
        representitive_slice = str2num(get(h.representitive_slice, 'String'));
        

        [unmixed_image, extra_channel_names] = k_means_unmixing(num_channels, num_timesteps, x_dim, y_dim, z_dim, num_fluorophores_to_unmix, channels_to_unmix, mixed_image, replicates,...
            scaled_signatures, multi_fluorophore_pixels, representitive_timestep, representitive_slice, infer_channel_names);
        uiresume
    end
end

function unmixed_image = simi_gui()

end

function unmixed_image = nnmf_gui(mixed_image)
    unmixed_image = nnmf_unmixing(mixed_image);
end


function [unmixed_image, extra_channel_names] = k_means_unmixing(num_channels, num_timesteps, x_dim, y_dim, z_dim, num_fluorophores_to_unmix, channels_to_unmix, mixed_image, replicates,...
    scaled_signatures, multi_fluorophore_pixels, representitive_timestep, representitive_slice, infer_channel_names)

    %background_as_cluster = true;
    use_input_intensities = true; %Setting this to false is good for debugging where certain clusters are
    maximum_iterations = 100;
    channels = 1:num_channels
    channels_to_leave = channels(~ismember(channels, channels_to_unmix));
    %num_fluorophores_to_unmix = num_fluorophores_to_unmix+background_as_cluster;
    channels_to_unmix
    
    disp(num_timesteps)
    disp(size(mixed_image))
    
    %It doesn't like doing kmeans on unsigned integers (understandibly)
    mixed_image = double(mixed_image);
    %save original pixel intensities for later
    unscaled_mixed_image = mixed_image;
      
    %Select only representitive timestep and slice
    if num_timesteps>1
        reordered_mixed_image = permute(mixed_image, [4 1 2 3 5]);
        reordered_mixed_image = reordered_mixed_image(:, :, :, :, representitive_timestep);
    else
        reordered_mixed_image = permute(mixed_image, [4 1 2 3]);
    end
    disp(size(reordered_mixed_image))
    
    if z_dim>1
        reordered_mixed_image = reordered_mixed_image(:, :, :, representitive_slice);
    end
    disp(size(reordered_mixed_image))
    
    %Normalize pixel intensities
    for c = 1:length(channels) %scale even the channel you're leaving alone so that softmaxing works. 
        mixed_image_channel = reordered_mixed_image(c, :, :);
        mu = mean(mixed_image_channel(:))
        sigma = std(mixed_image_channel(:))
        reordered_mixed_image(c, :, :) = (reordered_mixed_image(c, :, :)-mu)/sigma;
        mixed_image(:, :, :, c, :) = (mixed_image(:, :, :, c, :)-mu)/sigma; %Get z-scores for entire image
    end 
    
    if scaled_signatures
        %change so that it only includes channels to unmix
        disp("Softmaxing")
        reordered_mixed_image_channels_to_unmix = reordered_mixed_image(channels_to_unmix, :, :);
        mixed_image_channels_to_unmix = mixed_image(:, :, :, channels_to_unmix, :);
        
        reordered_mixed_image = exp(reordered_mixed_image)./sum(exp(reordered_mixed_image_channels_to_unmix), 1); %this is waaaaaaay faster
        mixed_image = exp(mixed_image)./sum(exp(mixed_image_channels_to_unmix), 4); 
    end

    disp("Finished scaling intensities")
    
    pixel_array = reordered_mixed_image(:, :);%image_to_pixel_array(mixed_image);
    pixel_array = permute(pixel_array, [2 1]);
    
    disp("reordered")

    %select just the channels you want to unmix
    pixel_array = pixel_array(:, channels_to_unmix); 


    close all;    
    vProgressDisplay = waitbar(0.2,'Spectral Unmixing:Running K-Means...');
    %This really does take a long time for big datasets. Running on just
    %one z-slice could help that
    disp('Running K-Means. The display may freeze but it is still working behind the scenes. This may take a few minutes for large datasets.')
    if multi_fluorophore_pixels
        min_objFunc = inf
        for i=1:replicates
            [cluster_centroids_i, U, objFunc] = fcm(pixel_array, num_fluorophores_to_unmix, [2, maximum_iterations, 1e-3, true]);
            if objFunc(end) <= min_objFunc
                min_objFunc = objFunc(end)
                cluster_centroids = cluster_centroids_i
            end
        end
    else
        [cluster_indices, cluster_centroids, sumd, D] = kmeans(pixel_array, num_fluorophores_to_unmix, 'Replicates', replicates, 'MaxIter', maximum_iterations, 'Display', 'iter');%, 'Start', initial_centroids);
    end
    disp('Finished Running k-means')
    close all;
    vProgressDisplay = waitbar(0.5,'Spectral Unmixing:Finished Running K-Means...');
    pause(0.01) %let the display catch up
    
    
    cluster_centroids_copy = cluster_centroids
    
    if infer_channel_names
        for c = 1:length(channels_to_unmix)
            [~, closest_cluster] = max(cluster_centroids_copy(:, c));
            cluster_centroids(c, :) = cluster_centroids_copy(closest_cluster, :)
            cluster_centroids_copy(closest_cluster, :) = [];
        end
        
        for c = length(channels_to_unmix)+1:num_fluorophores_to_unmix
            [~, next_cluster] = max(cluster_centroids_copy(:, 1));
            cluster_centroids(c, :) = cluster_centroids_copy(next_cluster, :)
            cluster_centroids_copy(next_cluster, :) = [];
            extra_channel_names(c-length(channels_to_unmix)) = "background";
        end
        
    else
        extra_channel_names = [];
    end

    cluster_centroids
    
    cluster_totals = zeros(num_fluorophores_to_unmix, 1);

    if not(multi_fluorophore_pixels)
        for i = 1:num_fluorophores_to_unmix
            cluster_totals(i) = sum(cluster_indices==i);
        end
        cluster_totals
    end

    
    num_output_channels = num_fluorophores_to_unmix+length(channels_to_leave);
    cluster_weights_image = zeros(x_dim, y_dim, z_dim, num_fluorophores_to_unmix, num_timesteps);
    cluster_weights_timestep = zeros(x_dim, y_dim, z_dim, num_fluorophores_to_unmix);
    distances = zeros(x_dim, y_dim, z_dim, num_fluorophores_to_unmix);
    cluster_center_broadcast = zeros(x_dim, y_dim, z_dim, length(channels_to_unmix), num_fluorophores_to_unmix);
    
    disp('Broadcasting cluster centers')
    %This takes a while as well when there are a lot of pixels. Is there a
    %way to do with matrix math?
    
    for cluster = 1:num_fluorophores_to_unmix
        cluster_center = reshape(cluster_centroids(cluster, :), 1, 1, 1, length(channels_to_unmix));
        cluster_center_broadcast(:, :, :, :, cluster) = repmat(cluster_center, x_dim, y_dim, z_dim);
    end
    close all;
    vProgressDisplay = waitbar(0.5,'Applying clustering to data');
    

    if multi_fluorophore_pixels
        for t = 1:num_timesteps
            disp(strcat("applying clustering to timestep ", int2str(t), " of ", int2str(num_timesteps)))
            waitbar(0.5+0.3*t/num_timesteps);
            for cluster = 1:num_fluorophores_to_unmix   
                pixel_values = double(mixed_image(:, :, :, channels_to_unmix, t));
                diff = pixel_values - cluster_center_broadcast(:, :, :, :, cluster);
                intermediate_step = vecnorm(diff, 2, 4); 
                distances(:, :, :, cluster) = squeeze(intermediate_step);
            end
            pause(0.01)
            inverse_square_weights = 1./distances.^2;
            inverse_square_weights_pixel_sums = sum(inverse_square_weights, 4);
            cluster_weights = inverse_square_weights./inverse_square_weights_pixel_sums;
            cluster_weights_timestep(:) = cluster_weights(:);
            cluster_weights_image(:, :, :, :, t) = cluster_weights_timestep;
        end
    else
        %
        cluster_weights = zeros(x_dim*y_dim*z_dim*num_timesteps, num_fluorophores_to_unmix);
        %if num_timesteps == 1 && z_dim == 1
        %    for i=1:x_dim*y_dim*z_dim*num_timesteps
        %        cluster_weights(i, cluster_indices(i)) = 1;
        %    end
        %    cluster_weights_image(:) = cluster_weights(:);
        %else
        for t = 1:num_timesteps
            cluster_weights_timestep = zeros(x_dim, y_dim, z_dim, num_fluorophores_to_unmix); %so that you don't get weird tails effects
            disp(strcat("applying clustering to timestep ", int2str(t), " of ", int2str(num_timesteps)))
            waitbar(0.5+0.3*t/num_timesteps);
            for cluster = 1:num_fluorophores_to_unmix   
                pixel_values = double(mixed_image(:, :, :, channels_to_unmix, t));
                diff = pixel_values - cluster_center_broadcast(:, :, :, :, cluster);
                intermediate_step = vecnorm(diff, 2, 4); 
                distances(:, :, :, cluster) = squeeze(intermediate_step);
            end
            pause(0.01)
            [~, cluster_indices] = min(distances, [], length(size(distances)));

            for x=1:x_dim
                for y = 1:y_dim
                    for z = 1:z_dim
                        cluster_weights_timestep(x,y,z,cluster_indices(x,y,z)) = 1;
                    end
                end
            end
            cluster_weights_image(:, :, :, :, t) = cluster_weights_timestep;
        end
        %end
    end

    %cluster_weights for each pixel sum to the total intensity of the channels
    %being unmixed after this step
    if use_input_intensities
        cluster_weights_image = cluster_weights_image .*max(unscaled_mixed_image(:, :, :, channels_to_unmix, :), [],  4); 
    else
        cluster_weights_image = cluster_weights_image * double(max(unscaled_mixed_image(:)));
    end

    unmixed_image = zeros(x_dim, y_dim, z_dim, num_output_channels, num_timesteps);

    if length(channels_to_leave)>0
        unmixed_image(:, :, :, 1:length(channels_to_leave), :) = unscaled_mixed_image(:, :, :, channels_to_leave, :);
    end
    unmixed_image(:, :, :, length(channels_to_leave)+1:end, :) = cluster_weights_image;
    

end %breakpoint

function unmixed_image = nnmf_unmixing(mixed_image)
    disp('starting nnmf unmixing')
    %This can't currently handle 4D data
    %This assumes # of input channels is also # of output channels because
    %that's all I've seen it do correctly


    %I think this has issues with the scale and datatype of the incoming
    %data similar to what k-means had at first
    
    disp(max(mixed_image(:)))
    mixed_image = double(mixed_image)./double(max(mixed_image(:)));
    disp(max(mixed_image(:)))
    
    dims = size(mixed_image);
    num_images = dims(3);
    num_channels = dims(4);
    num_labels = num_channels; %In naive case
    image_size = dims(1:2);
    epsilon = eps()*6;
    unmixed_image = zeros(dims);  
    num_cols = image_size(2);
    max_iter = 150;
    opt = statset('MaxIter', max_iter);
    n_pixels = prod(image_size);

    for slice = 1:num_images

        Y  = zeros(num_channels, n_pixels);
        for ch = 1:num_channels
            for col = 0:num_cols-1
                low = col*image_size(1)+1;
                high = col*image_size(1)+image_size(1);
                Y(ch, low:high) = mixed_image(:, col+1, slice, ch);
            end
        end


        A0 = transpose([[1 0 0]; [.3511 .6489 0]; [.108 .5023 .3896]]);
        [Ac, H] = nnmf(Y, num_labels, 'algorithm', 'als', 'w0', A0, 'h0', Y, 'options', opt); 


        Ac = Ac./sum(Ac);
        [vals, indices] = max(Ac, [], 2);
        Ac = Ac(:, indices);
        H = (transpose(Ac) * (Ac+epsilon))\transpose(Ac)*Y;

        for ch = 1:num_labels
            for col = 0:num_cols-1
                low = col*image_size(1)+1;
                high = col*image_size(1)+image_size(1);
                unmixed(:, col+1,slice, ch) = H(ch, low:high); 
            end
        end
    end


end

function return_results_to_imaris(unmixed_image, vDataSet, num_timesteps, vImarisApplication, infer_channel_names, extra_channel_names)


% Create a new channel
dims = size(unmixed_image);
num_output_channels = dims(4);
          
%channel_names = ["test 1", "test 2", "test 3", "test 4", "test 5", "test 6"];
% if infer_channel_names
%     %original_colors = vDataSet.GetChannelColorRGBA();
%     %vDataSet.SetChannelColorRGBA(0);
%     %output_channel_names = 1;
% else
%     disp("Functionality for not infering names is not yet set")
%     for c=1:num_output_channels
%         output_channel_names(c) = "Cluster + " + int2str(c);
%     end
% end

vDataSet.SetSizeC(num_output_channels);  


for t = 1:num_timesteps
    disp(strcat("returning timestep ", int2str(t), " of ", int2str(num_timesteps)))
    waitbar(0.8+0.2*t/num_timesteps)
    pause(0.01)
    for c = 1:num_output_channels
        %get channel name
        %channel_name = vImarisApplication.getChannelNames(c-1);

        basic_stack = unmixed_image(:, :, :, c, t);
        switch char(vDataSet.GetType())
            case 'eTypeUInt8'
                vDataSet.SetDataVolumeAs1DArrayBytes(uint8(basic_stack(:)), c-1, t-1); 
            case 'eTypeUInt16'
                vDataSet.SetDataVolumeAs1DArrayShorts(uint16(basic_stack(:)), c-1, t-1);
            case 'eTypeFloat'
                vDataSet.SetDataVolumeAs1DArrayFloats(single(basic_stack(:)), c-1, t-1);
            otherwise, error('Bad value for type');
        end
        %rename channel
        if infer_channel_names 
            if (c>(num_output_channels-length(extra_channel_names)))
                vDataSet.SetChannelName(c-1, extra_channel_names(c-(num_output_channels-length(extra_channel_names))));
                %vImarisDataSet.SetChannelName(vNumberOfChannels,['Distance to ', char(vImarisObject.GetName)]);
            end
        else
            vDataSet.SetChannelName(c-1, ("Channel" + int2str(c)));
        end
        
        
        
    end
end

close all;
vProgressDisplay = waitbar(1,'Done');
close(vProgressDisplay) %End progress bar display
vImarisApplication.SetDataSet(vDataSet);


end
