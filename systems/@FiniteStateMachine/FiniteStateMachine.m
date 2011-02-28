classdef FiniteStateMachine < RobotLibSystem

  % some restrictions on the mode systems:
  %  must be CT only 
  
  properties 
    modes={};       % cell array of systems representing each state (or mode)
    % transitions:
    target_mode={}; % target_mode{i}(j) describes the target for the jth transition out of the ith mode
    guard={};       % guard{i}{j} is for the jth transition from the ith mode
    update={};      % update{i}{j} is for the jth transition from the ith mode
    num_zcs = 0;    % number of zero-crossings.
    output_mode = true;
  end
  
  % construction
  methods
    function obj = FiniteStateMachine()
      obj = obj@RobotLibSystem(0,1,0,0,false,true);
    end
    
    function [obj,mode_num] = addMode(obj,mode_sys)
      if (getNumStates(mode_sys)>0 && ~mode_sys.isCT()) error('only CT modes are allowed for now'); end
      obj.modes = {obj.modes{:},mode_sys};
      mode_num = length(obj.modes);
      obj.target_mode = {obj.target_mode{:},[]};
      obj.guard = {obj.guard{:},{}};
      obj.update = {obj.update{:},{}};
      obj = setNumContStates(obj,max(getNumContStates(obj),getNumContStates(mode_sys)));
      obj = setNumInputs(obj,max(getNumInputs(obj),getNumInputs(mode_sys)));
      obj = setNumOutputs(obj,max(1+getNumContStates(obj),1+getNumContStates(mode_sys)));
      obj = setDirectFeedthrough(obj,isDirectFeedthrough(obj) || isDirectFeedthrough(mode_sys));
      obj = setTIFlag(obj,isTI(obj) && isTI(mode_sys));
    end
    
    function obj = addTransition(obj,from_mode_num,to_mode_num,guard,update,directFeedthrough,timeInvariant)
      % guard is a function pointer with style:  
      %    [phi,dphi] = guard(fsm_obj,t,mode_x,u)
      %    with phi a scalar, which indicates a transition when phi<=0.
      % update is a function pointer with style:
      %    [to_mode_xn,status,dto_mode_xn] = update(fsm_obj,t,mode_x,u)
      
      if (from_mode_num<1 || from_mode_num>length(obj.modes)) error('invalid from mode'); end
      if (to_mode_num<1 || to_mode_num>length(obj.modes)) error('invalid to mode'); end
      typecheck(guard,{'function_handle','inline'});
      if (~isempty(update)) typecheck(update,{'function_handle','inline'}); end
      tid = length(obj.target_mode{from_mode_num})+1;
      obj.target_mode{from_mode_num}(tid) = to_mode_num;
      obj.guard{from_mode_num}{tid} = guard;
      obj.update{from_mode_num}{tid} = update;
      obj = setDirectFeedthrough(obj,obj.isDirectFeedthrough() || directFeedthrough);
      obj = setTIFlag(obj,obj.isTI() && timeInvariant);
      obj.num_zcs = max(obj.num_zcs,tid);
    end
    
    function guard = and_guards(obj,varargin)
      % produces a single guard that is a logical 'and' of the variable
      % number of guards input.
      if (length(varargin)<2) error('should have at least two functions to and'); end
      for i=1:length(varargin)
        typecheck(varargin{i},{'function_handle','inline'});
      end
      guard = @(obj,t,x,u)and_guard_fun(obj,t,x,u,varargin{:});
      
      function [phi,dphi] = and_guard_fun(obj,t,x,u,varargin)
        if (nargout>1)
          for i=1:length(varargin)
            [phi(i),dphi{i}] = varargin{i}(obj,t,x,u);
          end
          [phi,ind] = max(phi);
          dphi = dphi{ind};
        else
          for i=1:length(varargin)
            phi(i) = varargin{i}(obj,t,x,u);
          end
          phi = max(phi);
        end
      end
    end  

    function guard = not_guard(obj,orig_guard)
      guard = @(obj,t,x,u)not_guard_fun(obj,t,x,u,orig_guard);
      
      function [phi,dphi] = not_guard_fun(obj,t,x,u,guard)
        if (nargout>1)
          [phi,dphi] = guard(obj,t,x,u);
          if (length(dphi)>1) error('not implemented yet'); end
          dphi{1} = -dphi{1};
        else
          phi = guard(obj,t,x,u);
        end
        phi = -phi;
      end
    end
    
  end

  % access methods
  methods 
    function mode_sys = getMode(obj,mode_num)
      if (mode_num<1 || mode_num>length(systems)) error('bad mode num'); end
      mode_sys = systems{mode_num};
    end
    
    function n = getNumZeroCrossings(obj)
      n = obj.num_zcs;
    end
  end
  
  % implementation
  methods
    function m = getInitialMode(obj)
      m=1;
    end

    function x0 = getInitialState(obj)
      m = getInitialMode(obj);
      x0 = [m; getInitialState(obj.modes{m})];
      % pad if necessary:
      x0 = [x0;repmat(0,1+getNumContStates(obj)-length(x0),1)];
    end
    
    function xcdot = dynamics(obj,t,x,u)
      m = x(1);
      xcdot = dynamics(obj.modes{m},t,x(2:end),u);
      % pad if necessary:
      xcdot = [xcdot;repmat(0,getNumContStates(obj)-length(xcdot),1)];
    end
    
    function y = output(obj,t,x,u)
      m = x(1);
      y = output(obj.modes{m},t,x(2:end),u);
      % pad if necessary:
      y = [y;repmat(0,getNumOutputs(obj)-length(y),1)];
      if (obj.output_mode) y = [m;y]; end
    end
    
    function zcs = guards(obj,t,x,u)
      m = x(1);
      zcs=[];
      for i=1:length(obj.target_mode{m})
        zcs(i) = obj.guard{m}{i}(obj,t,x(2:end),u);
      end
      % pad if necessary:
      zcs = [zcs;repmat(1,getNumZeroCrossings(obj)-length(zcs),1)];
    end
    
    function [xn,status] = transition_update(obj,t,x,u)
      status = 0;
      m = x(1);
      zcs = guards(obj,t,x,u);
      active_id = find(zcs<0);
      if (isempty(active_id)) % no transition (return the original state)
        xn = x;
        return;
      end
      if (length(active_id)>1) error('multiple guards tripped at the same time.  behavior is undefined.  consider reducing the step size'); end
      if (isempty(obj.update{m}{active_id}))
        mode_xn = x(2:end);
        status = 0;
      else
        [mode_xn,status] = obj.update{m}{active_id}(obj,t,x(2:end),u);
      end
      xn = [obj.target_mode{m}(active_id);mode_xn];
      % pad if necessary:
      xn = [xn;repmat(0,1+getNumContStates(obj)-length(xn),1)];
      if (any(guards(obj,t,xn,u)<0)), keyboard; end % useful for debugging successive zcs.
    end
  end
  
end