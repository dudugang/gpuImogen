function makeEnsightGeometryFile(SP, frameref, filename)
% This describes what the geometry file must output
% This must be followed TO THE LETTER and that INCLUDES SPACES
% See page 10 of Ensight Gold format PDF
GEOM = fopen([filename '.geom'], 'w');

% header stuff. six lines of exactly 80 chars each.
charstr = char(32*ones([400 1]));
charstr(1:8)     = 'C Binary';
charstr(81:93)   = 'Imogen export';
charstr(161:181) = 'Saved in Ensight Gold';
charstr(241:251) = 'node id off';
charstr(321:334) = 'element id off';
%charstr(401:407) = 'extents';
fwrite(GEOM, charstr, 'char*1');

% six floats, [xmin xmax ymin ymax zmin zmax]
extents = [0 0 0 0 0 0];

isUniform = 1;

if numel(frameref.dGrid{1}) == 1 % uniform spacing x
    extents(2) = frameref.dGrid{1} * max((size(frameref.mass, 1)-1), 1);
else
    extents(2) = sum(frameref.dGrid{1}(:,1,1));
    isUniform  = 0;
end

if numel(frameref.dGrid{2}) == 1 % uniform spacing y
    extents(4) = frameref.dGrid{2} * max((size(frameref.mass, 2)-1), 1);
else
    extents(4) = sum(frameref.dGrid{2}(1,:,1));
    isUniform  = 0;
end

if numel(frameref.dGrid{3}) == 1 % uniform spacing z
    extents(6) = frameref.dGrid{3} * max((size(frameref.mass, 3)-1), 1);
else
    extents(6) = sum(frameref.dGrid{3}(1,1,:));
    isUniform  = 0;
end

d = SP.returnInitializer();

if d.ini.geometry.pGeometryType == 2
    isUniform = 0;
    isCylindrical = 1;
else
    isCylindrical = 0;
end

%fwrite(GEOM, single(extents), 'float');

% part - exactly 80 chars
charstr = char(32*ones([80 1]));
charstr(1:4) = 'part';
fwrite(GEOM, charstr, 'char*1');

% NO Number of nodes - 1 int
%nnodes = prod(size(frameref.mass));
fwrite(GEOM, 1, 'int');

if isUniform % Easy-peasy
    % description line - exactly 80 chars
    % uniform block - exactly 80 c
    charstr = char(32*ones([160 1]));
    charstr(1:17) = 'simulation domain';
    charstr(81:93) = 'block uniform';
    fwrite(GEOM, charstr, 'char*1');

    % Write number of i j and k steps. 3 ints.
    domsize = size(frameref.mass);
    if numel(domsize) == 2; domsize(3) = 1; end
    fwrite(GEOM, domsize, 'int');

    orig_pos = [0 0 0 frameref.dGrid{1} frameref.dGrid{2} frameref.dGrid{3}];
    fwrite(GEOM, orig_pos, 'float');
elseif isCylindrical % must use curvilinear coordinates!!
disp('DEBUG WARNING: trying to emit cylindrical coordinates to ensight! hold on!');
    % description line - exactly 80 chars
    % uniform block - exactly 80 c
    charstr = char(32*ones([160 1]));
    charstr(1:17) = 'simulation domain';
    charstr(81:97) = 'block curvilinear';
    fwrite(GEOM, charstr, 'char*1');

    % Write number of i j and k steps. 3 ints.
    domsize = size(frameref.mass);
    if numel(domsize) == 2; domsize(3) = 1; end
    fwrite(GEOM, domsize, 'int');

    % This turd-tastic hack recreates the original geometry manager, for one node, containing the global geometry info
    g = GeometryManager(d.ini.geometry.globalDomainRez); % fake global geometry manager
    g.geometryCylindrical(d.ini.geometry.affine(1), round(2*pi/(d.ini.geometry.d3h(2)*d.ini.geometry.globalDomainRez(2))), d.ini.geometry.d3h(1), d.ini.geometry.affine(2), d.ini.geometry.d3h(3));

    % fetch positions of all coordinates
    [rmat, thmat, zmat] = g.ndgridSetIJK('pos');
    xmat = rmat .* cos(thmat);
    ymat = rmat .* sin(thmat);
    clear rmat thmat;

    fwrite(GEOM, xmat, 'float');
    fwrite(GEOM, ymat, 'float');
    fwrite(GEOM, zmat, 'float');
else
    % description line - exactly 80 chars
    % uniform block - exactly 80 c
    charstr = char(32*ones([160 1]));
    charstr(1:17) = 'simulation domain';
    charstr(81:97) = 'block rectilinear';
    fwrite(GEOM, charstr, 'char*1');

    % Write number of i j and k steps. 3 ints.
    domsize = size(frameref.mass);
    if numel(domsize) == 2; domsize(3) = 1; end
    fwrite(GEOM, domsize, 'int');

    ivec = cumsum(squish(frameref.dGrid{1}(:,1,1))) - frameref.dGrid{1}(1,1,1);
    jvec = cumsum(squish(frameref.dGrid{2}(1,:,1))) - frameref.dGrid{2}(1,1,1);
    kvec = cumsum(squish(frameref.dGrid{3}(1,1,:))) - frameref.dGrid{3}(1,1,1);

    if numel(ivec) ~= size(frameref.mass,1)
        ivec = (1:size(frameref.mass, 1))*frameref.dGrid{1}(1);
    end
    if numel(jvec) ~= size(frameref.mass,2)
        jvec = (1:size(frameref.mass, 2))*frameref.dGrid{2}(1);
    end
    if numel(kvec) ~= size(frameref.mass,3)
        kvec = (1:size(frameref.mass, 3))*frameref.dGrid{3}(1);
    end

    fwrite(GEOM, ivec, 'float');
    fwrite(GEOM, jvec, 'float');
    fwrite(GEOM, kvec, 'float');

end

fclose(GEOM);

end
