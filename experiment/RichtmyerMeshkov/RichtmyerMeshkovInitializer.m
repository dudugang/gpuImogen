classdef RichtmyerMeshkovInitializer < Initializer

% Heavy fluid at the bottom, light fluid on top. Have some non-uniform interface between them like a
% sinusoid, then launch a shock plane wave down into the interface. This shock will reflect off the
% interface non-uniformly, driving the heavy fluid into the light fluid like a jet.

%===================================================================================================
    properties (Constant = true, Transient = true) %                            C O N S T A N T  [P]

    end%CONSTANT
    
%===================================================================================================
    properties (SetAccess = public, GetAccess = public) %                           P U B L I C  [P]
        mach;
        numWave;
        waveHeight;
        massRatio;      % ratio of (low mass)/(high mass) for the flow regions.     double
    end %PUBLIC

%===================================================================================================
    properties (Dependent = true) %                                            D E P E N D E N T [P]
    end %DEPENDENT
    
%===================================================================================================
    properties (SetAccess = protected, GetAccess = protected) %                P R O T E C T E D [P]
    end %PROTECTED
    
%===================================================================================================
    methods %                                                                     G E T / S E T  [M]
        
%___________________________________________________________________________________________________ KelvinHelmholtzInitializer
        function obj = RichtmyerMeshkovInitializer(input)
            obj = obj@Initializer();
            obj.gamma            = 7/5;
            obj.runCode          = 'RM';
            obj.info             = 'Richtmyer-Meshkov instability test';
            obj.mode.fluid       = true;
            obj.mode.magnet      = false;
            obj.mode.gravity     = false;
            obj.cfl              = 0.85;
            obj.iterMax          = 1500;
            obj.mach             = 0.66;
            obj.activeSlices.xy  = true;
            obj.ppSave.dim2      = 25;

            obj.numWave                 = 1;
            obj.waveHeight         = .05;

            obj.bcMode.x = 'circ';
            obj.bcMode.y = 'const';
            obj.bcMode.z = 'mirror';
            
            obj.massRatio        = 5;
            obj.pureHydro        = true;
            obj.operateOnInput(input, [512 512 1]);

        end
        
    end%GET/SET
    
%===================================================================================================
    methods (Access = public) %                                                     P U B L I C  [M]       
    end%PUBLIC
    
%===================================================================================================    
    methods (Access = protected) %                                          P R O T E C T E D    [M]
        
%___________________________________________________________________________________________________ calculateInitialConditions
        function [fluids, mag, statics, potentialField, selfGravity] = calculateInitialConditions(obj)
        
            %--- Initialization ---%
            statics             = [];
            potentialField      = [];
            selfGravity         = [];
            
            geo                 = obj.geomgr;
            geo.makeBoxSize([1 1 1]);
            
            % Initialize Arrays
            [mass, mom, mag, ener] = geo.basicFluidXYZ();
            jumpConds              = HDJumpSolver(obj.mach^(-1), 0, obj.gamma);

            % Initialize parallelized vectors
            obj.dGrid           = 1./obj.grid;
            [X, Y, Z]             = geo.ndgridSetXYZ('pos');

            % Set various variables
            shockmargin         = 20*obj.dGrid(2); % Places the shock a short distance away from the peak of the sinusoid
            vpostshock          = jumpConds.v(1,1)-jumpConds.v(1,2); % Corrects post-shock velocity to form a standing shock
            wavepos             = .7;        % Determines the position of the wave on the y-axis
            preshockcorrect     = .8;   % Makes a small correction to the whole grid to capture the jet

            % Define the wave contact in parallel
            wave                = wavepos + obj.waveHeight*cos(obj.numWave*2*pi*X);
            postshock           = (Y < wavepos - obj.waveHeight - shockmargin); 
            heavy               = (Y >= wave);

            % Set parameters for heavy fluid and subtract pre-shock velocity to maintain position on the grid
            mass(heavy)         = obj.massRatio;
            mom(2,:,:,:)        = -jumpConds.v(1,2)*mass;

            % Set parameters for the shocked region
            mass(postshock)     = jumpConds.rho(2);
            mom(2,postshock)    = vpostshock*jumpConds.rho(2);
            ener(postshock)     = jumpConds.Pgas(2);

            % Make a small correction to the entire grid to capture the jet before it flows off-grid
            mom(2,:,:,:)        = mom(2,:,:,:)*preshockcorrect;

            % Calculate energy density array
            ener = ener/(obj.gamma - 1) ...                                             % internal
            + 0.5*squish(sum(mom.*mom,1))./mass ...                             % kinetic
            + 0.5*squish(sum(mag.*mag,1));                                      % magnetic

            fluids = obj.rhoMomEtotToFluid(mass, mom, ener);

            end
        end%PROTECTED       
%===================================================================================================    
    methods (Static = true) %                                                     S T A T I C    [M]
    end
end%CLASS
