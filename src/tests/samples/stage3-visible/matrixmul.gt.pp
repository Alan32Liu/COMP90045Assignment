proc main ()
    int i;
    int j;
    int k;
    int m[6, 6];
    int n[6, 6];
    int r[6, 6];
begin
    k := 0;
    i := 0;
    while i < 6 do
        j := 0;
        while j < 6 do
            k := k + 1;
            m[i, j] := k;
            n[5 - j, 5 - i] := k;
            j := j + 1;
        od
        i := i + 1;
    od
    i := 0;
    while i < 6 do
        j := 0;
        while j < 6 do
            k := 0;
            while k < 6 do
                r[i, j] := r[i, j] + (m[i, k] * n[k, j]);
                k := k + 1;
            od
            j := j + 1;
        od
        i := i + 1;
    od
    i := 0;
    while i < 6 do
        j := 0;
        while j < 6 do
            write r[i, j];
            write "  ";
            j := j + 1;
        od
        write "\n";
        i := i + 1;
    od
end
