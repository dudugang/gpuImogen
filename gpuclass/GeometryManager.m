classdef GeometryManager < handle
% Global Index Semantics: Translates global index requests to local ones for lightweight global array support
% x = GlobalIndexSemantics(context, topology): initialize
% TF = GlobalIndexSemantics('dummy'): Check if previous init'd
% x = GlobalIndexSemantics(): Retreive

    properties (Constant = true, Transient = true)
        haloAmt = 3;
        SCALAR = 1000;
        VECTOR = 1001;
    end

    properties (SetAccess = public, GetAccess = public, Transient = true)
        
    end % Public

    properties (SetAccess = public, GetAccess = public)
        context;
        topology;
        globalDomainRezPlusHalos; % The size of global input domain size + halo added on [e.g. 512 500]
        
        pLocalDomainOffset; % The offset of the local domain taking the lower left corner of the
                            % input domain (excluding halo).

        edgeInterior; % Marks if [left/right, x/y/z] side is interior (circular) or exterior (maybe not)
    end % Private

    properties (SetAccess = private, GetAccess = public)
        pGeometryType;
        globalDomainRez;   % The input global domain size, with no halo added [e.g. 500 500]
        localDomainRez;          % The size of the local domain + any added halo [256 500
        
        
        
        % The local parts of the x/y/z index counting vectors
        % Matlab format (from 1)
        localIcoords; localJcoords; localKcoords;
        
        affine; % Stores [dx dy dz] or [r0 z0]
        d3h; % The [dx dy dz] or [dr dphi dz] spacing
        pInnerRadius;   % Used only if geometryType = ENUM.GEOMETRY_CYLINDRICAL

        localXposition; localYposition; localZposition; % Used by cartesian
        localRposition; localPhiPosition;               % Used by cylindrical (uses Z too)
        
        % FIXME: Add spacing-vectors for calculating updates over nonuniform grids here
    end % Readonly

    properties (SetAccess = private, GetAccess = private)
        % Marks whether to wrap or continue counting at the exterior halo
        circularBCs;

        % Local indices such that validArray(nohaloXindex, ...) contains everything but the halo cells
        % Useful for array reducing operations
        nohaloXindex, nohaloYindex, nohaloZindex;
    end

    properties (Dependent = true)
        
    end % Dependent

    methods
        function obj = GeometryManager(globalResolution)
            % GlobalIndexSemantics sets up Imogen's global/local indexing
            % system. It automatically fetches itself the context & topology stored in ParallelGlobals
            
            parInfo      = ParallelGlobals();
            obj.context  = parInfo.context;
            obj.topology = parInfo.topology;
            
            if nargin < 1
                warning('GeometryManager received no resolution: going with 512x512x1; Call GIS.setup([nx ny nz]) to change.');
                globalResolution = [512 512 1];
            end

            obj.setup(globalResolution);
            obj.geometrySquare([0 0 0], [1 1 1]); % Set default geometry to cartesian, unit spacing
        end

        function package = serialize(self)
            % Converts the GIS object into a structure which can reinitialize itself
            % 'context',self.context, 'topology', self.topology, are excluded because they do not persist across invocations if restarting
            package = struct('globalDomainRezPlusHalos', self.globalDomainRezPlusHalos, ...
                             'localDomainRez', self.localDomainRez, 'pLocalDomainOffset',self.pLocalDomainOffset, ...
                             'globalDomainRez', self.globalDomainRez, 'edgeInterior', self.edgeInterior, ...
                             'pGeometryType', self.pGeometryType, 'pInnerRadius', self.pInnerRadius, ...
                             'localIcoords', self.localIcoords, 'localJcoords', self.localJcoords, ...
                             'localKcoords', self.localKcoords, 'circularBCs', self.circularBCs, ...
                             'nohaloXindex', self.nohaloXindex, 'nohaloYindex', self.nohaloYindex, ...
                             'nohaloZindex', self.nohaloZindex, 'affine', self.affine, 'd3h', self.d3h, ...
                             'localXposition', self.localXposition, 'localYposition', self.localYposition, ...
                             'localZposition', self.localZposition, 'localRposition', self.localRposition, ...
                             'localPhiPosition', self.localPhiPosition);
        end
        
        function deserialize(self, package)
            F = fields(package);
            for N = 1:numel(F)
                self.(F{N}) = package.(F{N});
            end
        end
        
        function obj = setup(obj, global_size)
            % setup(global_resolution) establishes a global resolution &
            % runs the bookkeeping for it.
            if numel(global_size) == 2; global_size(3) = 1; end

            dblhalo = 2*obj.haloAmt;
            
            obj.globalDomainRez = global_size;
            obj.globalDomainRezPlusHalos   = global_size + dblhalo*double(obj.topology.nproc).*double(obj.topology.nproc > 1);

            % Default size: Ntotal / Nproc
            propSize = floor(obj.globalDomainRezPlusHalos ./ double(obj.topology.nproc));
            
            % Compute offset
            obj.pLocalDomainOffset = (propSize-dblhalo).*double(obj.topology.coord);

            % If we're at the plus end of the topology in a dimension, increase proposed size to meet global domain resolution.
            for i = 1:obj.topology.ndim;
                if (double(obj.topology.coord(i)) == (obj.topology.nproc(i)-1)) && (propSize(i)*obj.topology.nproc(i) < obj.globalDomainRezPlusHalos(i))
                    propSize(i) = propSize(i) + obj.globalDomainRezPlusHalos(i) - propSize(i)*obj.topology.nproc(i);
                end
            end

            obj.localDomainRez = propSize;

            obj.edgeInterior(1,:) = double(obj.topology.coord > 0);
            obj.edgeInterior(2,:) = double(obj.topology.coord < (obj.topology.nproc-1));

            obj.circularBCs = [1 1 1];

            obj.updateGridVecs();
        end % Constructor

        function makeDimCircular(obj, dim)
            % makeDimCircular(1 <= dim <= 3) declares a circular BC on dim
            % Effect: Outer edge has a halo
            if (dim < 1) || (dim > 3); error('Dimension must be between 1 and 3\n'); end
            obj.circularBCs(dim) = 1;
            obj.updateGridVecs();
        end

        function makeDimNotCircular(obj, dim)
            % makeDimNotCircular(1 <= dim <= 3) declares a noncircular BC on dim
            % Effect: Outer edge does not have a halo.
            if (dim < 1) || (dim > 3); error('Dimension must be between 1 and 3\n'); end
            obj.circularBCs(dim) = 0;
            obj.updateGridVecs();
        end

        function makeBoxSize(obj, newsize)
            if obj.pGeometryType == ENUM.GEOMETRY_SQUARE
                if numel(newsize) ~= 3; newsize = obj.globalDomainRez * newsize(1) / obj.globalDomainRez(1); end
                obj.d3h = newsize ./ obj.globalDomainRez;
            end
            if obj.pGeometryType == ENUM.GEOMETRY_CYLINDRICAL
                if numel(newsize) ~= 3 % make the annulus (rin,rin+x) x (0,z=x) x (0,2pi)
                    width  = newsize(1);
                    height = newsize(1);
                    ang    = 2*pi;
                else
                    width  = newsize(1);
                    ang    = newsize(2);
                    height = newsize(3);
                end
                obj.d3h = [width ang height] ./ obj.globalDomainRez;
            end
            obj.updateGridVecs();
        end

        function geometrySquare(obj, zeropos, spacing)
            % geometrySquare([x0 y0 z0], [hx hy hz])
            % sets the (1,1,1) cell to have center at [x0 y0 z0]
            % and grid spacing to [hx hy hz]
            obj.pGeometryType = ENUM.GEOMETRY_SQUARE;
            obj.pInnerRadius = 1.0; % ignored

            if nargin >= 2;
                if numel(zeropos) ~= 3; zeropos = [1 1 1]*zeropos(1); end
            else
                zeropos = [0 0 0];
            end
            obj.affine = zeropos;   
            if nargin >= 3
                if numel(spacing) ~= 3; spacing = [1 1 1]*spacing(1); end
            else
                spacing = [1 1 1];
            end
            obj.d3h    = spacing;

            obj.updateGridVecs();
        end

        function geometryCylindrical(obj, Rin, M, dr, z0, dz)
            % geometryCylindrical(Rin, M, dr, z0, dz) sets the
            % annulus' innermost cell's center to Rin with spacing dr,
            % and sets dphi so we span 2*pi/M in angle.
            obj.pGeometryType = ENUM.GEOMETRY_CYLINDRICAL;
            obj.makeDimNotCircular(1); % updates grid vecs

	    % This is used in the low-level routines as the Rcenter of the innermost cell of this node...
            obj.pInnerRadius  = Rin + dr*(obj.localIcoords(1)-1);

            obj.affine = [Rin z0];
            dphi = 2*pi / (M*obj.globalDomainRez(2));
            obj.d3h = [dr dphi dz];

            obj.updateGridVecs();
        end
        
        function [u, v, w] = toLocalIndices(obj, x, y, z)
            % [u v w] = GIS.toLocalIndices(x, y, z) converts a global set of coordinates to 
            % local coordinates, and keeps only those in the local domain
            u = []; v = []; w = [];
            if (nargin == 2) && (size(x,2) == 3);
                z = x(:,3) - obj.pLocalDomainOffset(3);
                y = x(:,2) - obj.pLocalDomainOffset(2);
                x = x(:,1) - obj.pLocalDomainOffset(1);
  
                keep = (x>0) & (x<=obj.localDomainRez(1)) & (y>0) & (y<=obj.localDomainRez(2)) & (z>0) & (z<=obj.localDomainRez(3));
                u = [x(keep) y(keep) z(keep)];
                return;
            end
            if (nargin >= 2) && (~isempty(x)); x = x - obj.pLocalDomainOffset(1); u=x((x>0)&(x<=obj.localDomainRez(1))); end
            if (nargin >= 3) && (~isempty(y)); y = y - obj.pLocalDomainOffset(2); v=y((y>0)&(y<=obj.localDomainRez(2))); end
            if (nargin >= 4) && (~isempty(z)); z = z - obj.pLocalDomainOffset(3); w=z((z>0)&(z<=obj.localDomainRez(3))); end

        end

        function [x, y, z] = toCoordinates(obj, I0, Ix, Iy, Iz, h, x0)
        % [x y z] = toCoordinates(obj, I0, Ix, Iy, Iz, h, x0) returns (for n = {x, y, z})
        % (In - I0(n))*h(n) - x0(n), i.e.
        % I0 is an index offset, h the coordinate spacing and x0 the coordinate offset.
        % [] for I0 and x0 default to zero; [] for h defaults to 1; scalars are multiplied by [1 1 1]
        % Especially useful during simulation setup, converting cell indices to physical positions
        % to evaluate functions at.

        if nargin < 3; error('Must receive at least toCoordinates(I0, x)'); end
        % Throw duct tape at the arguments until glaring deficiencies are covered
        if numel(I0) ~= 3; I0 = [1 1 1]*I0(1); end
        if nargin < 4; Iy = []; end
        if nargin < 5; Iz = []; end
        if nargin < 6; h = [1 1 1]; end
        if numel(h) ~= 3; h = [1 1 1]*h(1); end
        if nargin < 7; x0 = [1 1 1]; end
        if numel(x0) ~= 3; x0 = [1 1 1]*x0(1); end

        if ~isempty(Ix); x = (Ix - I0(1))*h(1) - x0(1); end
        if ~isempty(Iy); y = (Iy - I0(2))*h(2) - x0(2); end
        if ~isempty(Iz); z = (Iz - I0(3))*h(3) - x0(3); end

        end

        function Y = evaluateFunctionOnGrid(obj, afunc)
        % Y = evaluateFunctionOnGrid(@func) calls afunc(x,y,z) using the
        % [x y z] returned by obj.ndgridSetIJK.
            [x, y, z] = obj.ndgridSetIJK();
            Y = afunc(x, y, z);
        end
        
        function localset = LocalIndexSet(obj, globalset, d)
        % Extracts the portion of ndgrid(1:globalsize(1), ...) visible to this node
        % Renders the 3 edge cells into halo automatically
        
            pLocalMax = obj.pLocalDomainOffset + obj.localDomainRez;

            if nargin == 3;
                q = globalset{d};
                localset =  q((q >= obj.pLocalDomainOffset(d)) & (q <= pLocalMax(d))) - obj.pLocalDomainOffset(d) + 1;
            else
                localset = cell(3,1);
                
                for n = 1:min(numel(obj.globalDomainRezPlusHalos), numel(globalset));
                    q = globalset{n};
                    localset{n} = q((q >= obj.pLocalDomainOffset(n)) & (q <= pLocalMax(n))) - obj.pLocalDomainOffset(n) + 1;
                end
            end
        end
        
        function LL = cornerIndices(obj)
        % Return the index of the lower left corner in both local and global coordinates
        % Such that subtracting them from a 1:size(array) will make the lower-left corner that isn't part of the halo [0 0 0] in local coords and whatever it is in global coords
        ndim = numel(obj.globalDomainRezPlusHalos);

            LL=[1 1 1; (obj.pLocalDomainOffset+1)]';
            for j = 1:ndim;
                LL(j,:) = LL(j,:) - 3*(obj.topology.nproc(j) > 1);
            end

        end

        function updateGridVecs(obj)
            % GIS.updateGridVecs(). Utility - upon change in global dims, recomputes x/y/z index
            % vectors
            ndim = numel(obj.globalDomainRezPlusHalos);

            x   = cell(ndim,1);
            lnh = cell(ndim,1);
            for j = 1:ndim;
                q = 1:obj.localDomainRez(j);
                % This line degerates to the identity operation if nproc(j) = 1
                q = q + obj.pLocalDomainOffset(j) - 3*(obj.topology.nproc(j) > 1);

                % If the edges are periodic, wrap coordinates around
                if (obj.topology.nproc(j) > 1) && (obj.circularBCs(j) == 1)
                    q = mod(q + obj.globalDomainRez(j) - 1, obj.globalDomainRez(j)) + 1;
                end
                x{j} = q;

                lmin = 1; lmax = obj.localDomainRez(j);
                if (obj.topology.coord(j) > 0) || ((obj.topology.nproc(j) > 1) && (obj.circularBCs(j) == 1));
                    lmin = 4;
                end
                if (obj.topology.coord(j) < obj.topology.nproc(j)-1) || ((obj.topology.nproc(j) > 1) && (obj.circularBCs(j) == 1));
                    lmax = lmax - 3;
                end

                lnh{j} = lmin:lmax;
            end
            
            if ndim == 2; x{3} = 1; end
            
            obj.localIcoords = x{1}; obj.localJcoords = x{2}; obj.localKcoords = x{3};
            obj.nohaloXindex = lnh{1}; obj.nohaloYindex = lnh{2}; obj.nohaloZindex = lnh{3};
            
            if obj.pGeometryType == ENUM.GEOMETRY_SQUARE
                obj.localXposition = obj.affine(1) + obj.d3h(1) * (obj.localIcoords-1);
                obj.localYposition = obj.affine(2) + obj.d3h(2) * (obj.localJcoords-1);
                obj.localZposition = obj.affine(3) + obj.d3h(3) * (obj.localKcoords-1);
            end
            
            if obj.pGeometryType == ENUM.GEOMETRY_CYLINDRICAL
                obj.localRposition = obj.affine(1) + obj.d3h(1)*(obj.localIcoords-1);
                obj.localPhiPosition = obj.d3h(2)*(obj.localJcoords-1);
                obj.localZposition = obj.affine(2) + obj.d3h(3)*(obj.localKcoords-1);
                
            end
        end

        function [u, v, w] = ndgridVecs(obj)
            % [u v w] = GIS.ndgridVecs() returns the x-, y- and z- index vectors
            u = obj.localIcoords; v = obj.localJcoords; w = obj.localKcoords;
        end

        % 123 = xyz, 456 = xy, xz, yz, 7 = xyz
        function [a, b, c] = buildOuterProduct(obj, dim, form)
           if any(dim == [1 2 3])
               
           end
           if any(dim == [4 5 6])
               
           end
           
           if dim == 7
               
           end
        end
        
        function [x, y, z] = ndgridSetIJK(obj, form)
            % [x y z] = ndgridsetIJK([form]) returns the part of
            % ndgrid( 1:grid(1), ...) that lives on this node.
            % If form is absent or 'coords', returns coordinates;
            % If form is 'pos' returns physical positions
            
            if nargin < 2; form = 'coords'; end
            
            if strcmp(form, 'coords')
                [x, y, z] = ndgrid(obj.localIcoords, obj.localJcoords, obj.localKcoords);
                return;
            end
            if strcmp(form, 'pos')
                if obj.pGeometryType == ENUM.SQUARE
                    [x, y, z] = ndgrid(obj.localXvector, obj.localYvector, obj.localZvector);
                elseif obj.pGeometryType == ENUM.CYLINDRICAL
                        [x, y, z] = ndgrid(obj.localRvector, obj.localPhivector, obj.localZvector);
                end
                return;
            end
            error('ndgridSetIJK called but form was %s, not ''coords'', or ''pos''.\n', form);
        end
        
        function [x, y] = ndgridSetIJ(obj, form)
            % See ndgridSetIJK doc; Returns [x y] arrays.
            % Note that offset/scale, if vector, must be 3 elements or
            % x(1)*[1 1 1] will be used instead
            
                        if nargin < 2; form = 'coords'; end
            
            if strcmp(form, 'coords')
                [x, y] = ndgrid(obj.localIcoords, obj.localJcoords);
                return;
            end
            if strcmp(form, 'pos')
                if obj.pGeometryType == ENUM.GEOMETRY_SQUARE
                    [x, y] = ndgrid(obj.localXvector, obj.localYvector);
                elseif obj.pGeometryType == ENUM.GEOMETRY_CYLINDRICAL
                        [x, y] = ndgrid(obj.localRposition, obj.localPhiPosition);
                end
                return;
            end
            error('ndgridSetIJ called but form was %s, not ''coords'', or ''pos''.\n', form);
        end
        
        function [y, z] = ndgridSetJK(obj, offset, scale)
            % See ndgridSetIJK doc; Returns [y z] arrays. 
            % Note that offset/scale, if vector, must be 3 elements or
            % x(1)*[1 1 1] will be used instead
            if nargin > 1;
                if nargin < 3; scale  = [1 1]; end;
                if nargin < 2; offset = [0 0]; end;
                [u, v, w] = obj.toCoordinates(offset, obj.localIcoords, obj.localJcoords, obj.localKcoords, scale, [0 0 0]);
                [y, z] = ndgrid(v, w);
            else
                [y, z] = ndgrid(obj.localJcoords, obj.localKcoords);
            end
        end
        
        function [x, z] = ndgridSetIK(obj, offset, scale)
            % See ndgridSetIJK doc; Returns [x z] arrays. 
            % Note that offset/scale, if vector, must be 3 elements or
            % x(1)*[1 1 1] will be used instead            
            if nargin > 1;
                if nargin < 3; scale  = [1 1]; end;
                if nargin < 2; offset = [0 0]; end;
                [u, v, w] = obj.toCoordinates(offset, obj.localIcoords, obj.localJcoords, obj.localKcoords, scale, [0 0 0]);
                [x, z] = ndgrid(u, w);
            else
                [x, z] = ndgrid(obj.localIcoords, obj.localKcoords);
            end
        end

        % Generic function that the functions below talk to
        function out = makeValueArray(obj, dims, dtype, val)
            makesize = [];
            switch dims;
                case 1; makesize = [obj.localDomainRez(1) 1 1];
                case 2; makesize = [1 obj.localDomainRez(2) 1];
                case 3; makesize = [1 1 obj.localDomainRez(3)];
                case 4; makesize = [obj.localDomainRez(1:2) 1];
                case 5; makesize = [obj.localDomainRez(1) 1 obj.localDomainRez(3)];
                case 6; makesize = [1 obj.localDomainRez(2:3)];
                case 7; makesize = obj.localDomainRez;
            end
            
            % Slap a 3 on the first dim to build a vector
            % This is stupid and REALLY should be exchanged (3 goes LAST)
            if (nargin > 2) && (dtype == obj.VECTOR); makesize = [3 makesize]; end

            % Generate an array of 0 if not given a value
            if (nargin < 4); val = 0; end

            out = val * ones(makesize);
        end 

        % These generate a set of zeros of the size of the part of the global grid residing on this node
        function O = zerosXY(obj, dtype);  if nargin < 2; dtype = obj.SCALAR; end; O = obj.makeValueArray(4, dtype, 0); end
        function O = zerosXZ(obj, dtype);  if nargin < 2; dtype = obj.SCALAR; end; O = obj.makeValueArray(5, dtype, 0); end
        function O = zerosYZ(obj, dtype);  if nargin < 2; dtype = obj.SCALAR; end; O = obj.makeValueArray(6, dtype, 0); end
        function O = zerosXYZ(obj, dtype); if nargin < 2; dtype = obj.SCALAR; end; O = obj.makeValueArray(7, dtype, 0); end

        % Or of ones
        function O = onesXY(obj, dtype);  if nargin < 2; dtype = obj.SCALAR; end; O = obj.makeValueArray(4, dtype, 1); end
        function O = onesXZ(obj, dtype);  if nargin < 2; dtype = obj.SCALAR; end; O = obj.makeValueArray(5, dtype, 1); end
        function O = onesYZ(obj, dtype);  if nargin < 2; dtype = obj.SCALAR; end; O = obj.makeValueArray(6, dtype, 1); end
        function O = onesXYZ(obj, dtype); if nargin < 2; dtype = obj.SCALAR; end; O = obj.makeValueArray(7, dtype, 1); end
        
        function [rho, mom, mag, ener] = basicFluidXYZ(obj)
            rho = ones(obj.localDomainRez);
            mom = zeros([3 obj.localDomainRez]);
            mag = zeros([3 obj.localDomainRez]);
            ener= ones(obj.localDomainRez);
        end
        
        function G = getNodeGeometry(obj)
            % Function returns an nx X ny X nz array whose (i,j,k) index contains the rank of the
            % node residing on the nx X ny X nz topology at that location.
            G = zeros(obj.topology.nproc);
            xi = mpi_allgather( obj.topology.coord(1) );
            yi = mpi_allgather( obj.topology.coord(2) );
            zi = mpi_allgather( obj.topology.coord(3) );
            i0 = xi + obj.topology.nproc(1)*(yi + obj.topology.nproc(2)*zi) + 1;
            G(i0) = 0:(numel(G)-1);
        end

        % This is the only function in GIS that references any part of the topology execpt .nproc or .coord
        function index = getMyNodeIndex(obj)
            index = double(mod(obj.topology.neighbor_left+1, obj.topology.nproc));
        end

        function slim = withoutHalo(obj, array)
            % slim = GIS.withoutHalo(fat), when passed an array of size equal to the node's
            % array size, returns the array with halos removed.

            cantdo = 0;
            for n = 1:3; cantdo = cantdo || (size(array,n) ~= obj.localDomainRez(n)); end
                
            cantdo = mpi_max(cantdo); % All nodes must receive an array of the appropriate size
  
            if cantdo;
                disp(obj.topology);
                disp([size(array); obj.localDomainRez]);
                error('Oh teh noez, rank %i received an array of invalid size!', mpi_myrank());
            end
      
            slim = array(obj.nohaloXindex, obj.nohaloYindex, obj.nohaloZindex);
        end

        function DEBUG_setTopoSize(obj, n)
            obj.topology.nproc = n;

            c = obj.circularBCs;
            obj.setup(obj.globalDomainRez);
            for x = 1:n; if c(x) == 0; obj.makeDimNotCircular(x); end; end
        end
        function DEBUG_setTopoCoord(obj,c)
            obj.topology.coord = c;
            c = obj.circularBCs;
            obj.setup(obj.globalDomainRez);
            for x = 1:n; if c(x) == 0; obj.makeDimNotCircular(x); end; end
        end

    end % generic methods

    methods (Access = private)

    end % Private methods

    methods (Static = true)

    end % Static methods

end
