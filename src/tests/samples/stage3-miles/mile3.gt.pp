proc main ()
    int x;
begin
    write "Integer, please: ";
    read x;
    while (x > 10) && (x < 100) do
        if x < 50 then
            x := x - 1;
        else
            x := x + 1;
        fi
    od
    if x < 50 then
        write "Went down";
    else
        write "Went up";
    fi
    write "\n";
end
