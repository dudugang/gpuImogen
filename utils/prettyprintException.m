function prettyprintException(ME, nmax, extendedString)
% > ME: A Matlab MException object
% > nmax: If present, maximum number of stack entries to print
% > extendedString: Displayed in line with the rest of the output if included.
% This function pretty-prints the MException's stack{} lines,

if nargin < 2; nmax = numel(ME.stack); end
if nmax <= 0; nmax = numel(ME.stack); end

fprintf('\n================================================================================\nRANK %i (host %s) HAS ENCOUNTERED AN EXCEPTION\nIDENTIFIER: %s\nMESSAGE   : %s\n',mpi_myrank(), getenv('HOSTNAME'), ME.identifier, ME.message);
if nargin >= 3;
    fprintf('USER MSG  : %s\n',extendedString);
end
fprintf('=========================== STACK BACKTRACE FOLLOWS ============================\n');

for n = 1:nmax;
    fprintf('%i: %s:%s at %i\n', n-1, ME.stack(n).file, ME.stack(n).name, ME.stack(n).line);
end
if nmax == 0
    disp('No stack: Error occured in interactive mode');
end

disp('================================================================================');

end
