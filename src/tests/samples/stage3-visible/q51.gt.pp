proc main ()
    int a[5];
begin
    a[0] := 1;
    a[1] := 1;
    a[a[1]] := 0;
    if a[a[1]] != 0 then
        write "What the?\n";
    fi
end
