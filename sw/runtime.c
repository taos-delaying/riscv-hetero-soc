#include <stddef.h>
#include <stdint.h>

/*
 * 最小裸机内存函数，供编译器或 NMSIS 产生的调用使用。
 * 按字节访问，允许未对齐地址；不依赖堆、外设或系统调用。
 * 本文件单独禁用 builtin/loop-to-libcall 优化，避免实现被改写为自调用。
 */

void *memcpy(void *destination, const void *source, size_t count)
{
    unsigned char *dst = (unsigned char *)destination;
    const unsigned char *src = (const unsigned char *)source;

    while (count != 0) {
        *dst++ = *src++;
        --count;
    }
    return destination;
}

void *memset(void *destination, int value, size_t count)
{
    unsigned char *dst = (unsigned char *)destination;

    while (count != 0) {
        *dst++ = (unsigned char)value;
        --count;
    }
    return destination;
}

void *memmove(void *destination, const void *source, size_t count)
{
    unsigned char *dst = (unsigned char *)destination;
    const unsigned char *src = (const unsigned char *)source;

    if (dst == src || count == 0)
        return destination;

    /* 当前目标是平坦地址空间；整数地址比较也适用于不同的 C 对象。 */
    if ((uintptr_t)dst < (uintptr_t)src) {
        while (count != 0) {
            *dst++ = *src++;
            --count;
        }
    } else {
        dst += count;
        src += count;
        while (count != 0) {
            *--dst = *--src;
            --count;
        }
    }
    return destination;
}

int memcmp(const void *left, const void *right, size_t count)
{
    const unsigned char *a = (const unsigned char *)left;
    const unsigned char *b = (const unsigned char *)right;

    while (count != 0) {
        if (*a != *b)
            return (int)*a - (int)*b;
        ++a;
        ++b;
        --count;
    }
    return 0;
}
