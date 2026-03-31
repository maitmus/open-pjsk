/*
 * mersoom-pow: fast SHA-256 proof-of-work solver (no dependencies)
 * Usage: mersoom-pow <seed> <target_prefix>
 * Output: nonce (decimal) on success, exit 1 on failure
 * Compile: gcc -O2 -o mersoom-pow mersoom-pow.c
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

/* Minimal SHA-256 implementation */
static const uint32_t K[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
};

#define RR(x,n) (((x)>>(n))|((x)<<(32-(n))))
#define S0(x) (RR(x,2)^RR(x,13)^RR(x,22))
#define S1(x) (RR(x,6)^RR(x,11)^RR(x,25))
#define s0(x) (RR(x,7)^RR(x,18)^((x)>>3))
#define s1(x) (RR(x,17)^RR(x,19)^((x)>>10))
#define CH(x,y,z) (((x)&(y))^((~(x))&(z)))
#define MAJ(x,y,z) (((x)&(y))^((x)&(z))^((y)&(z)))

static void sha256_block(uint32_t state[8], const uint8_t block[64]) {
    uint32_t w[64], a,b,c,d,e,f,g,h,t1,t2;
    for (int i=0;i<16;i++)
        w[i]=(uint32_t)block[i*4]<<24|(uint32_t)block[i*4+1]<<16|
             (uint32_t)block[i*4+2]<<8|block[i*4+3];
    for (int i=16;i<64;i++)
        w[i]=s1(w[i-2])+w[i-7]+s0(w[i-15])+w[i-16];
    a=state[0];b=state[1];c=state[2];d=state[3];
    e=state[4];f=state[5];g=state[6];h=state[7];
    for (int i=0;i<64;i++){
        t1=h+S1(e)+CH(e,f,g)+K[i]+w[i];
        t2=S0(a)+MAJ(a,b,c);
        h=g;g=f;f=e;e=d+t1;d=c;c=b;b=a;a=t1+t2;
    }
    state[0]+=a;state[1]+=b;state[2]+=c;state[3]+=d;
    state[4]+=e;state[5]+=f;state[6]+=g;state[7]+=h;
}

static void sha256(const uint8_t *data, size_t len, uint8_t out[32]) {
    uint32_t state[8]={0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
                       0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19};
    uint8_t block[64];
    size_t i=0;
    for (;i+64<=len;i+=64) sha256_block(state,(const uint8_t*)data+i);
    size_t rem=len-i;
    memcpy(block,data+i,rem);
    block[rem]=0x80;
    if (rem>=56){
        memset(block+rem+1,0,63-rem);
        sha256_block(state,block);
        memset(block,0,56);
    } else {
        memset(block+rem+1,0,55-rem);
    }
    uint64_t bits=len*8;
    for (int j=0;j<8;j++) block[56+j]=(uint8_t)(bits>>(56-j*8));
    sha256_block(state,block);
    for (int j=0;j<8;j++){
        out[j*4]=(uint8_t)(state[j]>>24);out[j*4+1]=(uint8_t)(state[j]>>16);
        out[j*4+2]=(uint8_t)(state[j]>>8);out[j*4+3]=(uint8_t)state[j];
    }
}

#define MAX_NONCE 100000000

int main(int argc, char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <seed> <target_prefix>\n", argv[0]);
        return 1;
    }
    const char *seed = argv[1];
    const char *prefix = argv[2];
    size_t seed_len = strlen(seed);
    size_t prefix_len = strlen(prefix);
    if (seed_len > 200) { fprintf(stderr, "seed too long\n"); return 1; }

    char buf[256];
    memcpy(buf, seed, seed_len);
    uint8_t hash[32];
    static const char hx[] = "0123456789abcdef";
    char hex[65];

    for (long nonce = 0; nonce < MAX_NONCE; nonce++) {
        int nl = sprintf(buf + seed_len, "%ld", nonce);
        sha256((uint8_t*)buf, seed_len + nl, hash);
        size_t cb = (prefix_len + 1) / 2;
        for (size_t i = 0; i < cb; i++) {
            hex[i*2]   = hx[(hash[i]>>4)&0xf];
            hex[i*2+1] = hx[hash[i]&0xf];
        }
        if (memcmp(hex, prefix, prefix_len) == 0) {
            printf("%ld\n", nonce);
            return 0;
        }
    }
    fprintf(stderr, "no solution found\n");
    return 1;
}
