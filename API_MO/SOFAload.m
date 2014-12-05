function Obj = SOFAload(fn,varargin)
%SOFALOAD 
%   Obj = SOFAload(FN) reads the SOFA object OBJ with all data from
%   a SOFA file FN. 
%
%   FN can point to a remote file (containing '://') or to a local file: 
%     Remote file: FN will be downloaded to a temporary directory and
%       loaded.
%     Local file: If existing, will be loaded. If not existing, it will be
%       downloaded from the internet repository given by SOFAdbURL. For
%       this, FN must begin with the local HRTF directory given by SOFAdbPath.
%
%   Obj = SOFAload(FN,'nodata') ignores the "Data." variables and
%   loads metadata only (variables and attributes).
%
%   Obj = SOFAload(FN,[START COUNT]) loads only COUNT number of 
%	measurements (dimension M) beginning with the index START. For remote
%   files, or local but not existing files, the full file will be downloaded.
%
%   Obj = SOFAload(FN,[START1 COUNT1],DIM1,[START2 COUNT2],DIM2,...) loads
%   only COUNT1 number of data in dimension DIM1 beginning with the index
%   START1, COUNT2 number of data in dimension DIM2 with the index START2
%   and so on.
%   
%   Obj = SOFAload(FN,...,'nochecks') loads the file but does not perform
%   any checks for correct conventions.
% 

% SOFA API - function SOFAload
% Copyright (C) 2012 Acoustics Research Institute - Austrian Academy of Sciences
% Licensed under the EUPL, Version 1.1 or � as soon they will be approved by the European Commission - subsequent versions of the EUPL (the "License")
% You may not use this work except in compliance with the License.
% You may obtain a copy of the License at: http://joinup.ec.europa.eu/software/page/eupl
% Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
% See the License for the specific language governing  permissions and limitations under the License. 

%% sort input arguments
inputargs={}; % for setting flags with SOFAarghelper
pDims=''; % for partial loading
pDimRange=[]; % for partial loading
jj=1; kk=1; ll=1;
for ii=1:length(varargin)
  if isnumeric(varargin{ii})
    pDimRange(jj,:)=varargin{ii};
    jj=jj+1;
    if ii==1
      inputargs{kk}=varargin{ii};
      kk=kk+1;
    end
  elseif strfind('MREN',varargin{ii})
    pDims(ll)=varargin{ii};
    ll=ll+1;
  elseif strcmp(varargin{ii},'nochecks')
    inputargs{kk}=varargin{ii};
  elseif strcmp(varargin{ii},'nodata')
    inputargs{kk}=varargin{ii};
    kk=kk+1;
  end
end
if ~isempty(pDimRange) && isempty(pDims)
  pDims='M';
end

%% set flags with SOFAarghelper
definput.keyvals.Index=[];
definput.flags.type={'data','nodata'};
definput.flags.data={'checks','nochecks'};
[flags,kv]=SOFAarghelper({'Index'},definput,inputargs);

%% check number of input arguments for partial loading
if ~(length(pDims)==size(pDimRange,1) || isempty(kv.Index)), error('Missing dimension or range for partial loading'), end

%% check file name
fn=SOFAcheckFilename(fn);

%% check if local or remote and download if necessary
if strfind(fn,'://')
  % remote path: download as temporary
  newfn=[tempname '.sofa'];
  urlwrite(fn, newfn);
else
  newfn=fn;
  if ~exist(fn,'file') % file does not exist? 
    warning(['File not found: ' fn]);
      % local path: replace SOFAdbPath by SOFAdbURL, download to SOFAdbPath 
    if length(fn)>length(SOFAdbPath) % fn is longer than SOFAdbPath?
      if strcmp(SOFAdbPath,fn(1:length(SOFAdbPath))) % fn begins with SOFAdbPath
        webfn=fn(length(SOFAdbPath)+1:end);
        webfn(strfind(webfn,'\'))='/';
        webfn=[SOFAdbURL regexprep(webfn,' ','%20')];        
        disp(['Downloading ' fn(length(SOFAdbPath)+1:end) ' from ' SOFAdbURL]);
        [f,stat]=urlwrite(webfn,fn);
        if ~stat
          error(['Could not download file: ' webfn]);
        end
      else % fn not existing and not beginning with SOFAdbPath --> error
        error(['Unable to read file ''' fn ''': no such file']);
      end
    else % fn not existing and shorter than SOFAdbPath --> error
        error(['Unable to read file ''' fn ''': no such file']);
    end
  end
end 

%% Load the object
if flags.do_nodata, Obj=NETCDFload(newfn,'nodata'); end;
if flags.do_data, 
  if isempty(kv.Index),
    Obj=NETCDFload(newfn,'all');
  else
    [Obj]=NETCDFload(newfn,pDimRange,pDims);
  end
end

%% Return if no checks should be performed
if flags.do_nochecks, return; end;

%% Check if SOFA conventions
if ~isfield(Obj,'GLOBAL_Conventions'), error('File is not a valid SOFA file'); end
if ~strcmp(Obj.GLOBAL_Conventions,'SOFA'), error('File is not a valid SOFA file'); end
if ~isfield(Obj,'GLOBAL_SOFAConventions'), error('Information about SOFA conventions is missing'); end
try
	X=SOFAgetConventions(Obj.GLOBAL_SOFAConventions,'m');
catch
	error('Unsupported SOFA conventions');
end

%% Check if DataType is present
if ~isfield(Obj,'GLOBAL_DataType'), error('DataType is missing'); end
%if ~strcmp(Obj.GLOBAL_DataType,X.GLOBAL_DataType), error('Wrong DataType'); end remove because this might be corrected in upgradeconventions

%% Ensure backwards compatibility
modified=1;
while modified, [Obj,modified]=SOFAupgradeConventions(Obj); end

%% If data loaded, check if correct data format
if ~flags.do_nodata,
	if ~isfield(Obj,'Data'), error('Data is missing'); end
	f=fieldnames(X.Data);
	for ii=1:length(f)
    if ~isfield(Obj.Data,f{ii})
      Obj.Data.(f{ii})=X.Data.(f{ii});
      Obj.API.Dimensions.Data.(f{ii})=X.API.Dimensions.Data.(f{ii});
      warning(['Data.' f{ii} ' was missing, set to default']);
    end
	end
	Obj=SOFAupdateDimensions(Obj);
end

%% Check if mandatory variables are present
f=fieldnames(X);
for ii=1:length(f)
	if ~isfield(Obj,f{ii})
    Obj.(f{ii})=X.(f{ii});
    if ~strfind(f{ii},'_'),
      Obj.API.Dimensions.(f{ii})=X.API.Dimensions.(f{ii});
    end
    warning([f{ii} ' was missing, set to default']);
  end
end

