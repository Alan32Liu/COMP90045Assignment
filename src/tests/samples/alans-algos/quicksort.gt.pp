proc main ()
    int numbers[10];
    int i;
    int n;
begin
    write "Quicksort of 10 numbers!\n";
    i := 0;
    while i < 10 do
        write "Please type number ";
        write i + 1;
        write ": ";
        read numbers[i];
    od
    call quicksort(numbers, 0, 10);
end

proc quicksort (ref int array, val int start, val int n)
    int first_eq;
    int first_gt;
begin
    if size > 1 then
        call partition(array, start, n, first_eq, first_gt);
        call quicksort(array, start, first_eq);
        call quicksort(array, first_gt, n - first_gt);
    fi
end

proc partition (ref int array, val int start, val int n, ref int first_eq, ref int first_gt)
    int pivot;
    int next;
    int fe;
    int fg;
begin
    pivot := start;
    next := start;
    fe := start;
    fg := n;
    while next < fg do
        if numbers[next] < numbers[pivot] then
            call int_swap(numbers[fe], numbers[next]);
            fe := fe + 1;
            next := next + 1;
        else
            if numbers[next] = numbers[pivot] then
                fg := fg - 1;
                call int_swap(numbers[next], numbers[fg]);
            else
                next := next + 1;
            fi
        fi
    od
    first_eq := fe;
    first_gt := fg;
end

proc int_swap (ref int a, ref int b)
    int temp;
begin
    temp := a;
    a := b;
    b := temp;
end
