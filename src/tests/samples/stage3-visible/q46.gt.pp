proc f (val float x)
begin
    x := x + 1;
    write x;
    write "\n";
end

proc main ()
    float n;
begin
    n := 41;
    call f(n);
    write n;
    write "\n";
end
