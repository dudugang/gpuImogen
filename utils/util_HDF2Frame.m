function frame = util_HDF2Frame(hname, options)
%function frame = util_Frame2HDF(hname)
% loads the hdf5 file at 'hname' and returns Imogen saveframe 'frame'.

if nargin < 2; options = 'nothing'; end
metaonly = strcmpi(options, 'metaonly');

frame.time = struct('history',[], 'time', [], 'iterMax', [], 'timeMax', [], 'wallMax', [], 'iteration', [], 'started', []);
frame.time.history = h5read(hname, '/timehist');

timeatts = {'time', 'iterMax', 'timeMax', 'wallMax', 'iteration', 'started'};
for i = 1:5
    frame.time.(timeatts{i}) = h5readatt(hname, '/timehist', timeatts{i});
end

% this shouldn't be here, but it was before so it still is.
frame.iter = h5readatt(hname, '/', 'iter');

% Grab the parallel struct info.
% This is dumped into the global directory as attributes because these are all small scalars... okay whatever.
frame.parallel = struct('geometry', [], 'globalDims', [], 'myOffset', [], 'haloBits', [], 'haloAmt', []);
paratts = {'geometry', 'globalDims', 'myOffset', 'haloBits', 'haloAmt'};

for i = 1:5
    frame.parallel.(paratts{i}) = h5readatt(hname, '/', ['par_ ' paratts{i}]);
end
frame.parallel.globalDims = transpose(frame.parallel.globalDims);
frame.parallel.myOffset = transpose(frame.parallel.myOffset);


frame.gamma = h5readatt(hname, '/', 'gamma');

frame.about = h5readatt(hname, '/', 'about');
frame.ver   = h5readatt(hname, '/', 'ver');

frame.dGrid = cell([1 3]);
frame.dGrid{1} = h5read(hname, '/dgridx');
frame.dGrid{2} = h5read(hname, '/dgridy');
frame.dGrid{3} = h5read(hname, '/dgridz');

if metaonly; return; end

varmode = 1;

frame.mass = h5read(hname, '/fluid1/mass');
try
    frame.momX = h5read(hname, '/fluid1/momX');
catch ohboy
    varmode = 2;
    frame.velX = h5read(hname, '/fluid1/velX');
end

if varmode == 1
    frame.momY = h5read(hname, '/fluid1/momY');
    frame.momZ = h5read(hname, '/fluid1/momZ');
    frame.ener = h5read(hname, '/fluid1/ener');
else
    frame.velY = h5read(hname, '/fluid1/velY');
    frame.velZ = h5read(hname, '/fluid1/velZ');
    frame.eint = h5read(hname, '/fluid1/eint');
end

q = h5info(hname, '/');

if ish5group(q, '/fluid2')
    if varmode == 1
        frame.mass2 = h5read(hname, '/fluid2/mass');
        frame.momX2 = h5read(hname, '/fluid2/momX');
        frame.momY2 = h5read(hname, '/fluid2/momY');
        frame.momZ2 = h5read(hname, '/fluid2/momZ');
        frame.ener2 = h5read(hname, '/fluid2/ener');
    else
        frame.mass2 = h5read(hname, '/fluid2/mass');
        frame.velX2 = h5read(hname, '/fluid2/velX');
        frame.velY2 = h5read(hname, '/fluid2/velY');
        frame.velZ2 = h5read(hname, '/fluid2/velZ');
        frame.eint2 = h5read(hname, '/fluid2/eint');
    end
end

frame.magX = h5read(hname, '/mag/X');
frame.magY = h5read(hname, '/mag/Y');
frame.magZ = h5read(hname, '/mag/Z');

end

function tf = ish5group(info, name)

for q = 1:numel(info.Groups)
    if strcmp(info.Groups(q).Name, name); tf = 1; return; end
end

tf = 0;

end
