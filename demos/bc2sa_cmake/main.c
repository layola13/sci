static int scale(int x) {
    return x * 3;
}

int demo(int a, int b) {
    int total = a + b;
    if (total > 4) {
        return scale(total);
    }
    return 0;
}
