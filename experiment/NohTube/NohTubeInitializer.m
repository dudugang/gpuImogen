classdef NohTubeInitializer < Initializer
    %===================================================================================================
    properties (Constant = true, Transient = true) %                            C O N S T A N T  [P]
        
    end%CONSTANT
    
    %===================================================================================================
    properties (SetAccess = public, GetAccess = public) %                           P U B L I C  [P]
        v0;    % Initial implosion speed
        rho0;  % Initial density
        r0;    % Radius of implosion
               % For 1D, r0 < 0 = prior to wall impact
        
        M0;    % Mach (large for analytical soln to work)

        halfspace;
    end %PUBLIC
    
    %===================================================================================================
    properties (Dependent = true) %                                            D E P E N D E N T [P]
    end %DEPENDENT
    
    %===================================================================================================
    properties (SetAccess = protected, GetAccess = protected) %                P R O T E C T E D [P]
    end %PROTECTED
    
    %===================================================================================================
    methods %                                                                     G E T / S E T  [M]
        
        %___________________________________________________________________________ SodShockTubeInitializer
        function obj = NohTubeInitializer(input)
            obj                  = obj@Initializer();
            obj.gamma            = 5/3;
            obj.runCode          = 'NT';
            obj.info             = 'Noh tube implosion.';
            obj.mode.fluid       = true;
            obj.mode.magnet      = false;
            obj.mode.gravity     = false;
            obj.cfl              = 0.85;
            obj.iterMax          = 150;
            obj.ppSave.dim1      = 10;
            obj.ppSave.dim3      = 25;
            
            obj.operateOnInput(input, [1024, 1, 1]);

            obj.bcMode.x         = ENUM.BCMODE_CONSTANT;
            obj.bcMode.y         = ENUM.BCMODE_CONSTANT;
            obj.bcMode.z         = ENUM.BCMODE_CONSTANT;
            obj.useHalfspace([0 0 0]);
            
            obj.pureHydro = 1;
            
            obj.rho0 = 1;
            obj.r0 = -0.8;
            obj.v0 = -1;
            obj.M0 = 3;
            
            obj.useHalfspace([0 0 0]);
        end
        
        
    end%GET/SET
    
    %===================================================================================================
    methods (Access = public) %                                                     P U B L I C  [M]
        function useHalfspace(self, direct)
            if numel(direct) == 1; direct = [1 1 1]*direct; end

            self.halfspace = direct;
        end

        function setupHalfspaces(self)
            if numel(self.halfspace) == 1; self.halfspace = [1 1 1]*self.halfspace; end
            rez = self.geomgr.globalDomainRez;
            
            ext = ENUM.BCMODE_CONSTANT;
            
            if self.halfspace(1)
                self.bcMode.x = {ENUM.BCMODE_MIRROR, ext};
            else
                self.bcMode.x = {ext, ext};
            end
            if self.halfspace(2) && (rez(2) > 1)
                self.bcMode.y = {ENUM.BCMODE_MIRROR, ext};
            else
                self.bcMode.y = {ext, ext};
            end
            if rez(3) > 1
                if self.halfspace(3)
                    self.bcMode.z = {ENUM.BCMODE_MIRROR, ext};
                else
                    self.bcMode.z = {ext, ext};
                end
            else
                self.bcMode.z = {ENUM.BCMODE_CIRCULAR, ENUM.BCMODE_CIRCULAR};
            end
        end
    end%PUBLIC
    
    %===================================================================================================
    methods (Access = protected) %                                          P R O T E C T E D    [M]
        
        %___________________________________________________________________________________________________ calculateInitialConditions
        function [fluids, mag, statics, potentialField, selfGravity] = calculateInitialConditions(obj)
            
            %--- Initialization ---%
            %            obj.runCode           = [obj.runCode upper(obj.direction)];
            statics               = [];
            potentialField        = [];
            selfGravity           = [];
            
            geo = obj.geomgr;
            rez = geo.globalDomainRez;
            
            obj.setupHalfspaces();

            half = floor(rez/2);
            needDia = [2 2 2].*(rez > 1);
            
            % Use halfspaces if negative-edge boundaries are mirrors
            if strcmp(obj.bcMode.x{1}, ENUM.BCMODE_MIRROR); half(1) = 3; needDia(1) = 1; end
            if strcmp(obj.bcMode.y{1}, ENUM.BCMODE_MIRROR); half(2) = 3; needDia(2) = 1; end
            if rez(3) > 1
                if strcmp(obj.bcMode.z{1}, ENUM.BCMODE_MIRROR); half(3) = 3; needDia(3)=1; end
            end
            
            geo.makeBoxSize(needDia);
            geo.makeBoxOriginCoord(half);
            [X, Y, Z] = geo.ndgridSetIJK('pos');
            
            spaceDim = 1;
            if rez(2) > 1; spaceDim = spaceDim + 1; end
            if rez(3) > 1; spaceDim = spaceDim + 1; end
            
            if spaceDim > 1
                generator = NohTubeColdGeneral(obj.rho0, 1, obj.M0);
                % 1 = p0 (init pressure) is IGNORED for multi-dim problem
                % I do not know the solution/ICs for d > 1
                R = sqrt(X.^2+Y.^2+Z.^2);
                Rmax = max(R(:));
                Rmin = 0;
                dynr = Rmax - Rmin;
                Rsolve = Rmin:.0001*dynr:Rmax;
            else
                generator = NohTubeExactPlanar(obj.rho0, 1, obj.M0);
                Rsolve = X;
            end
            
            [mass, mom, mag, ener] = geo.basicFluidXYZ();
            
            [rho, vradial, Pini] = generator.solve(spaceDim, Rsolve, obj.r0);
            
            % fixme - is setting T = 1 appropriate?
            Pini(rho< obj.minMass) = obj.minMass/(obj.gamma - 1);
            rho(rho < obj.minMass) = obj.minMass;
            
            switch spaceDim
                case 1
                    mass = rho;
                    px = mass.*vradial;
                    py = zeros(size(mass));
                    pz = zeros(size(mass));
                    ener = .5*mass.*(vradial.^2) + Pini /(obj.gamma-1);
                case 2
                    mass = interp1(Rsolve, rho, R);
                    prad = interp1(Rsolve, rho.*vradial, R);
                    px = prad .* X ./ R;
                    py = prad .* Y ./ R;
                    pz = zeros(size(mass));
                    ener = interp1(Rsolve, Pini/(obj.gamma-1), R) + .5*(px.^2+py.^2)./mass;
                case 3
                    mass = interp1(Rsolve, rho, R);
                    prad = interp1(Rsolve, rho.*vradial, R);
                    px = prad .* X ./ R;
                    py = prad .* Y ./ R;
                    pz = prad .* Z ./ R;
                    ener = interp1(Rsolve, Pini/(obj.gamma-1), R) + .5*(px.^2+py.^2+pz.^2)./mass;
            end
            
            mom(1,:,:,:) = px;
            mom(2,:,:,:) = py;
            mom(3,:,:,:) = pz;
            
            if ~obj.saveSlicesSpecified
                obj.activeSlices.xyz = true;
            end
            
            fluids = obj.rhoMomEtotToFluid(mass, mom, ener);
            
        end
        
    end%PROTECTED
    
    %===================================================================================================
    methods (Static = true) %                                                     S T A T I C    [M]
        
    end
end%CLASS
