// file-upload.c — Upload a file to console via Clovershell stdin
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <libusb.h>

#define CS_VID 0x1F3A
#define CS_PID 0xEFE8
#define CMD_PING 0
#define CMD_PONG 1
#define CMD_EXEC_NEW_REQ 9
#define CMD_EXEC_NEW_RESP 10
#define CMD_EXEC_STDOUT 13
#define CMD_EXEC_STDERR 14
#define CMD_EXEC_RESULT 15
#define CMD_EXEC_KILL_ALL 17
#define CMD_EXEC_STDIN 12

static libusb_device_handle *h;
static int usb_w(const void *d, int l) { int s=0; return libusb_bulk_transfer(h,0x01,(void*)d,l,&s,1000); }
static int usb_r(void *d, int l, int *a, int t) { *a=0; return libusb_bulk_transfer(h,0x81,d,l,a,t); }
static int cs_send(uint8_t cmd, uint8_t arg, const void *p, uint16_t l) {
    uint8_t *pkt=malloc(4+l); pkt[0]=cmd; pkt[1]=arg; pkt[2]=l&0xFF; pkt[3]=(l>>8)&0xFF;
    if(l>0&&p) memcpy(pkt+4,p,l); int r=usb_w(pkt,4+l); free(pkt); return r;
}

int main(int argc, char **argv) {
    if(argc<3){fprintf(stderr,"Usage: %s <local-file> <remote-path>\n",argv[0]);return 1;}
    setbuf(stdout,NULL);
    FILE *f=fopen(argv[1],"rb"); if(!f){perror("fopen");return 1;}
    fseek(f,0,SEEK_END); size_t sz=ftell(f); fseek(f,0,SEEK_SET);
    uint8_t *data=malloc(sz); fread(data,1,sz,f); fclose(f);
    printf("Uploading %s (%zu bytes) -> %s\n",argv[1],sz,argv[2]);

    libusb_init(NULL);
    h=libusb_open_device_with_vid_pid(NULL,CS_VID,CS_PID);
    if(!h){printf("No device\n");return 1;}
    if(libusb_kernel_driver_active(h,0)==1) libusb_detach_kernel_driver(h,0);
    libusb_claim_interface(h,0);

    uint8_t buf[65536]; int actual;
    cs_send(CMD_EXEC_KILL_ALL,0,NULL,0); usleep(50000);
    while(usb_r(buf,sizeof(buf),&actual,100)==0&&actual>0);
    cs_send(CMD_PING,0,NULL,0); usb_r(buf,sizeof(buf),&actual,2000);
    if(actual<4||buf[0]!=CMD_PONG){printf("No PONG\n");return 1;}

    char cmd[512]; snprintf(cmd,sizeof(cmd),"cat > %s",argv[2]);
    cs_send(CMD_EXEC_NEW_REQ,0,cmd,strlen(cmd));
    usleep(300000);
    while(usb_r(buf,sizeof(buf),&actual,100)==0&&actual>0);

    size_t off=0, chunk=8192;
    while(off<sz){
        size_t n=sz-off<chunk?sz-off:chunk;
        cs_send(CMD_EXEC_STDIN,0,data+off,(uint16_t)n);
        off+=n;
        if(off%(chunk*4)==0){usleep(10000);while(usb_r(buf,sizeof(buf),&actual,10)==0&&actual>0);}
        printf("\r  %zu / %zu (%d%%)",off,sz,(int)(off*100/sz));
    }
    printf("\n");
    usleep(300000);
    // Kill to close stdin/EOF
    cs_send(16,0,NULL,0); usleep(500000);
    while(usb_r(buf,sizeof(buf),&actual,200)==0&&actual>0);
    printf("Upload complete.\n");

    libusb_release_interface(h,0); libusb_close(h); libusb_exit(NULL); free(data);
    return 0;
}
