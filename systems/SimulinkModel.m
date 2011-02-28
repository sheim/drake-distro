classdef SimulinkModel < DynamicalSystem
% An interface class for a state-space dynamical system (also a simulink model)
%  with a single (vector) input u 
%  and a single (vector) state x composed of a combination of continuous time and discrete time variables, which is also the output
                                                 
  % constructor
  methods
    function obj = SimulinkModel(mdl)
      load_system(mdl);
      obj.mdl = mdl;
      sys = feval(mdl,[],[],[],'sizes');
      obj.num_xc = sys(1);
      obj.num_xd = sys(2);
      obj.num_y = sys(3);
      obj.num_u = sys(4);
    end
  end
  
  % default methods - these should be implemented or overwritten
  % 
  methods
    function n = getNumContStates(obj)
      n = obj.num_xc;
    end
    function n = getNumDiscStates(obj)
      n = obj.num_xd;
    end
    function n = getNumInputs(obj)
      n = obj.num_u;
    end
    function n = getNumOutputs(obj)
      n = obj.num_y;
    end
    function ts = getSampleTime(obj)
      [sys,x0,str,ts] = feval(obj.mdl,[],[],[],'sizes');
    end
    function mdl = getModel(obj)
      mdl = obj.mdl;
    end
    
    function x0 = getInitialState(obj)
      x0 = Simulink.BlockDiagram.getInitialState(obj.mdl);
      x0 = stateStructureToVector(obj,x0);
    end
    
    function xcdot = dynamics(obj,t,x,u)
      x = stateVectorToStructure(obj,x);
      if (~strcmp(get_param(obj.mdl,'SimulationStatus'),'paused'))
        feval(obj.mdl,[],[],[],'compile');
      end
      xcdot = feval(obj.mdl,t,x,u,'derivs');
      
      % the following two lines are a bizarre work-around to a bug I've
      % submitted to the mathworks.  they should be deleted if i figure out
      % what's going on.
      Simulink.BlockDiagram.getInitialState(obj.mdl);
      xcdot = feval(obj.mdl,t,x,u,'derivs');

      xcdot = stateStructureToVector(obj,xcdot);
    end
    
    function xdn = update(obj,t,x,u)
      x = stateVectorToStructure(obj,x);
      if (~strcmp(get_param(obj.mdl,'SimulationStatus'),'paused'))
        feval(obj.mdl,[],[],[],'compile');
      end
      xdn = feval(obj.mdl,t,x,u,'update');
      xdn = stateStructureToVector(obj,xdn);
    end
    
    function y = output(obj,t,x,u)
      x = stateVectorToStructure(obj,x);
      if (~strcmp(get_param(obj.mdl,'SimulationStatus'),'paused'))
        feval(obj.mdl,[],[],[],'compile');
      end
      y = feval(obj.mdl,t,x,u,'outputs');
    end
    
  end

  properties (SetAccess=private, GetAccess=private)
    num_xc; % number of continuous state variables
    num_xd; % number of dicrete(-time) state variables
    num_x;  % dimension of x (= num_xc + num_xd)
    num_u;  % dimension of u
    num_y;  % dimension of the output y
    mdl;    % a string name for the simulink model
  end
  
  
end