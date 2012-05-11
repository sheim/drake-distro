function megaclear() 
% Attempts to clear everything (classes, simulink, java, mex, ...) except breakpoints 

% Note: Must be a function so we can save breakpoint variables

    current_breakpoints = dbstatus('-completenames');

    force_close_system();
    evalin('base', 'clear all classes java mex');
    
    dbstop(current_breakpoints);
    
end