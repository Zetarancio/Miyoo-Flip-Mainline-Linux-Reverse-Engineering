#include<stdio.h>
#include<stdlib.h>
#include<unistd.h>
#include<sys/types.h>     
#include<sys/stat.h>       
#include<fcntl.h>   
#include<termios.h> 
#include<errno.h>
#include<string.h>    
#include<unistd.h>      
#include<pthread.h> 

#include<stdint.h> 

#include <linux/input.h>
#include "ukey.h"



//====================== joypad cal ========================= 
#define DEBUG_AXIS           (0)
#define TRIMUI_AXIS_RANGE    (32760)
#define TRIMUI_AXIS_MAX      (32760)
#define TRIMUI_AXIS_MIN      (-32760)
//#define TRIMUI_AXIS_SCALE(x)    (x * 300 / 256)
#define TRIMUI_AXIS_SCALE(x)    (x)

struct PK_CAL
{
    int x_min;
    int x_max;
    int y_min;
    int y_max;
    int x_zero;
    int y_zero;    
};


//20240414 for miyoo355
#define PK_ADC_DEFAULT_MAX_X   (200)
#define PK_ADC_DEFAULT_ZERO_X  (130)
#define PK_ADC_DEFAULT_MIN_X   (85)

#define PK_ADC_DEFAULT_MAX_Y   (200)
#define PK_ADC_DEFAULT_ZERO_Y  (130)
#define PK_ADC_DEFAULT_MIN_Y   (85)


//static int PK_ADC_DEAD_ZONE       =  (TRIMUI_AXIS_RANGE >> 3);
static int PK_ADC_DEAD_ZONE_SQUA  =  (TRIMUI_AXIS_RANGE >> 3) * (TRIMUI_AXIS_RANGE >> 3);
static int PK_REPORT_THRESHOLD    = (TRIMUI_AXIS_RANGE >> 8);

#define JOYPAD_CONFIG_FILE_LEFT     "/userdata/joypad.config"
#define JOYPAD_CONFIG_FILE_RIGHT    "/userdata/joypad_right.config"

static struct PK_CAL s_cal_l;
static struct PK_CAL s_cal_r;

static int getKeyValueDefault(const char * str, const char * key, int defaultValue)
{
	int index;
	char buf[16];
	const char * p = strstr(str, key);
	if (!p) 
		return defaultValue;

	p = strchr(p, '=');
	if (!p) 
		return defaultValue;

	memset(buf, 0, sizeof(buf));
	memcpy(buf, p + 1, 4);

	index = defaultValue;
	sscanf(buf, "%d", &index);
	return index;
}


int fileToMem(const char * path, void * data)
{
	int len, fileLen;
	FILE * fp = fopen(path, "r");
	if (!fp) {
		//printf("can not open %s\n", path);
		return 0;
	}
	fseek(fp, 0, SEEK_END);
	fileLen = ftell(fp);
	//printf("file %s len=%d\n", path, fileLen);
	fseek(fp, 0, SEEK_SET);
	len = fread(data, 1, fileLen, fp);
	fclose(fp);
	return len;
}

static void defaule_cal_config(struct PK_CAL * cal)
{
    printf("defaule_cal_config\n");
    if(!cal)
        return;
    cal->x_min = PK_ADC_DEFAULT_MIN_X;
	cal->x_max = PK_ADC_DEFAULT_MAX_X;
	cal->y_min = PK_ADC_DEFAULT_MIN_Y;
	cal->y_max = PK_ADC_DEFAULT_MAX_Y;
	cal->x_zero = PK_ADC_DEFAULT_ZERO_X;
	cal->y_zero = PK_ADC_DEFAULT_ZERO_Y;
}

static struct PK_CAL pk_read_cal_config(const char * configFile)
{
    struct PK_CAL cal;
	char configBuf[4096];
	memset(configBuf, 0, sizeof(configBuf));
	fileToMem(configFile, configBuf);

    // x_min=83
    // x_max=195
    // y_min=74
    // y_max=226
    // x_zero=134
    // y_zero=148

    cal.x_min = getKeyValueDefault(configBuf, "x_min", PK_ADC_DEFAULT_MIN_X);
	cal.x_max = getKeyValueDefault(configBuf, "x_max", PK_ADC_DEFAULT_MAX_X);
	cal.y_min = getKeyValueDefault(configBuf, "y_min", PK_ADC_DEFAULT_MIN_Y);
	cal.y_max = getKeyValueDefault(configBuf, "y_max", PK_ADC_DEFAULT_MAX_Y);
	cal.x_zero = getKeyValueDefault(configBuf, "x_zero", PK_ADC_DEFAULT_ZERO_X);
	cal.y_zero = getKeyValueDefault(configBuf, "y_zero", PK_ADC_DEFAULT_ZERO_Y);

    if(cal.x_max == cal.x_zero || cal.x_min == cal.x_zero)
        defaule_cal_config(&cal);
    if(cal.y_max == cal.y_zero || cal.y_min == cal.y_zero)
        defaule_cal_config(&cal);

    printf("pk_read_cal_config: [%d %d %d] [%d %d %d]\n", 
        cal.x_min,
        cal.x_zero,
        cal.x_max,
        cal.y_min,
        cal.y_zero,
        cal.y_max
    );
    return cal;
}

int pk_frame_to_axis_x(struct PK_CAL * cal, int rawX)
{
    if(!cal)
        return rawX;

    // if(rawX > 0 && rawX < PK_ADC_DEAD_ZONE)
    //     return 0;

    // if(rawX < 0 && rawX > -(PK_ADC_DEAD_ZONE))
    //     return 0;

    int value = 0;
    if(rawX > cal->x_zero)
    {
        value = (rawX - cal->x_zero) * TRIMUI_AXIS_RANGE / (cal->x_max - cal->x_zero);
        value = TRIMUI_AXIS_SCALE(value);
        if(value > TRIMUI_AXIS_RANGE)
            value = TRIMUI_AXIS_RANGE;
    }

    if(rawX < cal->x_zero)
    {
        value =  (rawX - cal->x_zero) * TRIMUI_AXIS_RANGE / (cal->x_zero - cal->x_min);
        value = TRIMUI_AXIS_SCALE(value);
        if(value < -TRIMUI_AXIS_RANGE)
            value = -TRIMUI_AXIS_RANGE;
    }
    return value;
}

int pk_frame_to_axis_y(struct PK_CAL * cal, int rawY)
{
    if(!cal)
        return rawY;

    // if(rawY > 0 && rawY < PK_ADC_DEAD_ZONE)
    //     return 0;

    // if(rawY < 0 && rawY > -(PK_ADC_DEAD_ZONE))
    //     return 0;

    int value = 0;
    if(rawY > cal->y_zero)
    {
        value = (rawY - cal->y_zero) * TRIMUI_AXIS_RANGE / (cal->y_max - cal->y_zero);
        value = TRIMUI_AXIS_SCALE(value);
        if(value > TRIMUI_AXIS_RANGE)
            value = TRIMUI_AXIS_RANGE;

    }

    if(rawY < cal->y_zero)
    {
        value = (rawY - cal->y_zero) * TRIMUI_AXIS_RANGE / (cal->y_zero - cal->y_min);
        value = TRIMUI_AXIS_SCALE(value);
        if(value < -TRIMUI_AXIS_RANGE)
            value = -TRIMUI_AXIS_RANGE;

    }

    return value;
}

//====================== joypad cal end ======================



int trimui_uart_open(const char *port)
{
    int fd;
    fd = open(port, O_RDWR | O_NOCTTY | O_NDELAY);
    if (fd < 0)
    {
        perror("Can't Open Serial Port");
        return -1;
    }

    if (fcntl(fd, F_SETFL, 0) < 0)
    {
        printf("fcntl failed!\n");
        return -1;
    }
    else
    {
        //printf("fcntl=%d\n", fcntl(fd, F_SETFL, 0));
    }
#if 0 // raymanfeng    
    if(0 == isatty(STDIN_FILENO))    
    {    
        printf("standard input is not a terminal device\n");    
        return -1;    
    }    
    else    
    {    
        printf("isatty success!\n");    
    }
#endif
    printf("fd=%d\n", fd);
    return fd;
}

void trimui_uart_Close(int fd)
{
    close(fd);
}

int trimui_uart_set(int fd, int speed, int flow_ctrl, int databits, int stopbits, int parity)
{
    int i;
    int speed_arr[] = {B115200, B19200, B9600, B4800, B2400, B1200, B300};
    int name_arr[] = {115200, 19200, 9600, 4800, 2400, 1200, 300};

    struct termios options;

    if (tcgetattr(fd, &options) != 0)
    {
        perror("SetupSerial 1");
        return -1;
    }

    for (i = 0; i < sizeof(speed_arr) / sizeof(int); i++)
    {
        if (speed == name_arr[i])
        {
            cfsetispeed(&options, speed_arr[i]);
            cfsetospeed(&options, speed_arr[i]);
        }
    }

    options.c_cflag |= CLOCAL;
    options.c_cflag |= CREAD;

    switch (flow_ctrl)
    {

    case 0:
        options.c_cflag &= ~CRTSCTS;
        break;

    case 1:
        options.c_cflag |= CRTSCTS;
        break;
    case 2:
        options.c_cflag |= IXON | IXOFF | IXANY;
        break;
    }

    options.c_cflag &= ~CSIZE;
    switch (databits)
    {
    case 5:
        options.c_cflag |= CS5;
        break;
    case 6:
        options.c_cflag |= CS6;
        break;
    case 7:
        options.c_cflag |= CS7;
        break;
    case 8:
        options.c_cflag |= CS8;
        break;
    default:
        fprintf(stderr, "Unsupported data size\n");
        return -1;
    }

    switch (parity)
    {
    case 'n':
    case 'N':
        options.c_cflag &= ~PARENB;
        options.c_iflag &= ~INPCK;
        break;
    case 'o':
    case 'O':
        options.c_cflag |= (PARODD | PARENB);
        options.c_iflag |= INPCK;
        break;
    case 'e':
    case 'E':
        options.c_cflag |= PARENB;
        options.c_cflag &= ~PARODD;
        options.c_iflag |= INPCK;
        break;
    case 's':
    case 'S':
        options.c_cflag &= ~PARENB;
        options.c_cflag &= ~CSTOPB;
        break;
    default:
        fprintf(stderr, "Unsupported parity\n");
        return -1;
    }

    switch (stopbits)
    {
    case 1:
        options.c_cflag &= ~CSTOPB;
        break;
    case 2:
        options.c_cflag |= CSTOPB;
        break;
    default:
        fprintf(stderr, "Unsupported stop bits\n");
        return -1;
    }

    options.c_oflag &= ~OPOST;
    options.c_lflag &= ~(ICANON | ECHO | ECHOE | ISIG);

    // raymanfeng+
    // 0x0D 0x0A
    options.c_iflag &= ~(INLCR | ICRNL | IGNCR);
    options.c_oflag &= ~(ONLCR | OCRNL);

    //raymanfeng for 0x11
    options.c_iflag &= ~(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON);

    options.c_cc[VTIME] = 1;
    options.c_cc[VMIN] = 1;

    tcflush(fd, TCIFLUSH);

    if (tcsetattr(fd, TCSANOW, &options) != 0)
    {
        perror("com set error!\n");
        return -1;
    }
    return 0;
}

int trimui_uart_recv(int fd, char *rcv_buf, int data_len)
{
    int len, fs_sel;
    fd_set fs_read;

    struct timeval time;

    FD_ZERO(&fs_read);
    FD_SET(fd, &fs_read);

    time.tv_sec = 10;
    time.tv_usec = 0;

    fs_sel = select(fd + 1, &fs_read, NULL, NULL, &time);
    if (fs_sel)
    {
        len = read(fd, rcv_buf, data_len);
        return len;
    }

    return -1;
}

int trimui_uart_send(int fd, char *send_buf, int data_len)
{
    int len = 0;

    len = write(fd, send_buf, data_len);
    if (len == data_len)
    {
        printf("send data is %s\n", send_buf);
        return len;
    }
    else
    {
        tcflush(fd, TCOFLUSH);
        return -1;
    }
}

void dump_cmd_frame(const char * buf, int len)
{
    int i;
    //printf("dump_cmd_frame: \n");
    for (i = 0; i < len; i++)
    {
        printf(" %02X", buf[i] & 0xFF);
    }
    printf("\n");
}


#define MIYOO_NODE_JOYSTICK    "/dev/ttyS1"
#define MIYOO_NODE_IO          "/dev/miyooio"
#define MIYOOIO_DATA_COUNT     (32)

#define TM_PLAYER_MAGIC         0xFF
#define TM_PLAYER_MAGIC_END     0xFE

#define RETRO_DEVICE_ID_JOYPAD_B        0
#define RETRO_DEVICE_ID_JOYPAD_Y        1
#define RETRO_DEVICE_ID_JOYPAD_SELECT   2
#define RETRO_DEVICE_ID_JOYPAD_START    3
#define RETRO_DEVICE_ID_JOYPAD_UP       4
#define RETRO_DEVICE_ID_JOYPAD_DOWN     5
#define RETRO_DEVICE_ID_JOYPAD_LEFT     6
#define RETRO_DEVICE_ID_JOYPAD_RIGHT    7
#define RETRO_DEVICE_ID_JOYPAD_A        8
#define RETRO_DEVICE_ID_JOYPAD_X        9
#define RETRO_DEVICE_ID_JOYPAD_L       10
#define RETRO_DEVICE_ID_JOYPAD_R       11
#define RETRO_DEVICE_ID_JOYPAD_L2      12
#define RETRO_DEVICE_ID_JOYPAD_R2      13
#define RETRO_DEVICE_ID_JOYPAD_L3      14
#define RETRO_DEVICE_ID_JOYPAD_R3      15
#define RETRO_MIYOO355_ID_MENU         16
#define RETRO_MIYOO355_ID_VOLUP        17
#define RETRO_MIYOO355_ID_VOLDOWN      18
#define RETRO_MIYOO355_ID_POWER        19


//FF 80 9A 88 93 FE
struct TRIMUI_PAD_FRAME
{
    uint8_t magic;
    uint8_t axisYL;
    uint8_t axisXL;
    uint8_t axisYR;
    uint8_t axisXR;
    uint8_t magicEnd;
};

#define  TRIMUI_PAD_FRAME_LEN      6  //sizeof(struct TRIMUI_PAD_FRAME)

static struct TRIMUI_PAD_FRAME s_frame_l, s_frame_r, s_last_l, s_last_r;
static int s_io_data[MIYOOIO_DATA_COUNT];
static int s_io_data_last[MIYOOIO_DATA_COUNT];
static int s_lock_suspend = 0;

struct tm_map
{
	int port; //player1/2/3/4
	int keymask;
	int keycode; //Linux event
};

struct tm_map_axis
{
	int port; //player1/2/3/4
	int keymask;
	int axis; //Linux event
    int value;
};

struct tm_map_turbo
{
	int port; //player1/2/3/4
	int keymask;
	const char * node; // /tmp/miyoo_inputd/turbo_a
    const char * label;
};


static struct tm_map s_tm_map[] =
{
#if 0
	{0, RETRO_DEVICE_ID_JOYPAD_A,       BTN_A},
	{0, RETRO_DEVICE_ID_JOYPAD_B,       BTN_B},
	{0, RETRO_DEVICE_ID_JOYPAD_X,       BTN_X},
	{0, RETRO_DEVICE_ID_JOYPAD_Y,       BTN_Y},
#else
    //xbox pad layout
	{0, RETRO_DEVICE_ID_JOYPAD_A,       BTN_B},
	{0, RETRO_DEVICE_ID_JOYPAD_B,       BTN_A},
	{0, RETRO_DEVICE_ID_JOYPAD_X,       BTN_Y},
	{0, RETRO_DEVICE_ID_JOYPAD_Y,       BTN_X},
#endif
	{0, RETRO_DEVICE_ID_JOYPAD_L,       BTN_TL},
	{0, RETRO_DEVICE_ID_JOYPAD_R,       BTN_TR},
	{0, RETRO_DEVICE_ID_JOYPAD_SELECT,  BTN_SELECT},
	{0, RETRO_DEVICE_ID_JOYPAD_START,   BTN_START},
	{0, RETRO_DEVICE_ID_JOYPAD_L3,      BTN_THUMBL},
	{0, RETRO_DEVICE_ID_JOYPAD_R3,      BTN_THUMBR},
	{0, RETRO_MIYOO355_ID_MENU,         BTN_MODE},

	// {0, RETRO_DEVICE_ID_JOYPAD_UP,      BTN_DPAD_UP},
	// {0, RETRO_DEVICE_ID_JOYPAD_DOWN,    BTN_DPAD_DOWN},
	// {0, RETRO_DEVICE_ID_JOYPAD_LEFT,    BTN_DPAD_LEFT},
	// {0, RETRO_DEVICE_ID_JOYPAD_RIGHT,   BTN_DPAD_RIGHT},

};

static struct tm_map_axis s_tm_map_axis[] =
{
#if 1
	{0, RETRO_DEVICE_ID_JOYPAD_UP,      ABS_HAT0Y, -1},
	{0, RETRO_DEVICE_ID_JOYPAD_DOWN,    ABS_HAT0Y, 1},
	{0, RETRO_DEVICE_ID_JOYPAD_LEFT,    ABS_HAT0X, -1},
	{0, RETRO_DEVICE_ID_JOYPAD_RIGHT,   ABS_HAT0X, 1},
#endif
    {0, RETRO_DEVICE_ID_JOYPAD_L2,      ABS_Z,     255},
    {0, RETRO_DEVICE_ID_JOYPAD_R2,      ABS_RZ,    255},
};


static int s_enable_turbo = 0;
static uint32_t s_turbo_bits = 0;

struct tm_map_turbo s_tm_map_turbo[] =
{
    {0, RETRO_DEVICE_ID_JOYPAD_A,   "/tmp/miyoo_inputd/turbo_a",   "MIYOO KEY A"  },
	{0, RETRO_DEVICE_ID_JOYPAD_B,   "/tmp/miyoo_inputd/turbo_b",   "MIYOO KEY B"  },
	{0, RETRO_DEVICE_ID_JOYPAD_X,   "/tmp/miyoo_inputd/turbo_x",   "MIYOO KEY X"  },
	{0, RETRO_DEVICE_ID_JOYPAD_Y,   "/tmp/miyoo_inputd/turbo_y",   "MIYOO KEY Y"  },
	{0, RETRO_DEVICE_ID_JOYPAD_R,   "/tmp/miyoo_inputd/turbo_r",   "MIYOO KEY R"  },
    {0, RETRO_DEVICE_ID_JOYPAD_R2,  "/tmp/miyoo_inputd/turbo_r2",  "MIYOO KEY R2" },
	{0, RETRO_DEVICE_ID_JOYPAD_L,   "/tmp/miyoo_inputd/turbo_l",   "MIYOO KEY L"  },
	{0, RETRO_DEVICE_ID_JOYPAD_L2,  "/tmp/miyoo_inputd/turbo_l2",  "MIYOO KEY L2" },
};


static void trimui_check_turbo_settting()
{
    int i;
    for(i = 0; i < ARRAY_SIZE(s_tm_map_turbo); i++)
    {
        uint32_t keymask = 1 << s_tm_map_turbo[i].keymask;
        if(!access(s_tm_map_turbo[i].node, F_OK))
        {
            if(!(s_turbo_bits & keymask))
                printf("enable turbo: %s\n", s_tm_map_turbo[i].label);
            s_turbo_bits |= keymask;
        }
        else
        {
            if(s_turbo_bits & keymask)
                printf("disable turbo:%s\n", s_tm_map_turbo[i].label);
            s_turbo_bits &= ~keymask;
        }
    }

    if(!access("/tmp/miyoo_inputd/enable_turbo_input", F_OK))
        s_enable_turbo = 1;
    else
        s_enable_turbo = 0;
}

static void trimui_do_turbo()
{
    static int s_toggle = 0;
    uint32_t mask = 0;
    if(!s_enable_turbo)
        return;

// s_io_data[MIYOOIO_DATA_COUNT];

//    for(int i = 0; i <= MIYOOIO_DATA_COUNT; i++)
    for(int i = 0; i <= RETRO_DEVICE_ID_JOYPAD_R2; i++)
    {
        mask = 1 << i;
        if(s_io_data[i] && (s_turbo_bits & mask))
        {
            if(s_toggle)
                s_io_data[i] = 0;
        }
    }
    s_toggle = !s_toggle;
}

static int key_pressed(int index)
{
    if(s_io_data[index] && !s_io_data_last[index])
        return 1;
    return 0;
}

static int key_released(int index)
{
    if(!s_io_data[index] && s_io_data_last[index])
        return 1;
    return 0;
}

static int axis_hold(int axis, struct tm_map_axis * map, int count)
{
    int i;
    for(i = 0; i < count; i++)
    {
        if ((axis == map[i].axis))
        {
            if(s_io_data[map[i].keymask])
                return 1;
        }
    }
    return 0;
}

static int report_axis_lr()
{
    int x, y;
    static int lastXL = -1;
    static int lastYL = -1;
    static int lastXR = -1;
    static int lastYR = -1;

    x = s_frame_l.axisXL;
    y = s_frame_l.axisYL;
    //trimui_vaxis(0, ABS_Y, value);

    if(DEBUG_AXIS) printf("Left :\t%d,%d ->", x, y);
    x = pk_frame_to_axis_x(&s_cal_l, x);
    y = pk_frame_to_axis_y(&s_cal_l, y);

    if((x * x + y * y) < PK_ADC_DEAD_ZONE_SQUA)
    {
        x = 0;
        y = 0;
    }
    if(DEBUG_AXIS) printf(" %d,%d \t\t", x, y);

    if(abs(x - lastXL) > PK_REPORT_THRESHOLD)
    {
        if(abs(x) < TRIMUI_AXIS_RANGE)
            trimui_vaxis(0, ABS_X, x);
        lastXL = x;
    }

    if(abs(y - lastYL) > PK_REPORT_THRESHOLD)
    {
        if(abs(y) < TRIMUI_AXIS_RANGE)
            trimui_vaxis(0, ABS_Y, y);
        lastYL = y;
    }


    x = s_frame_l.axisXR;
    y = s_frame_l.axisYR;
    //trimui_vaxis(0, ABS_Y, value);

    if(DEBUG_AXIS) printf("Right :\t%d,%d ->", x, y);
    x = pk_frame_to_axis_x(&s_cal_r, x);
    y = pk_frame_to_axis_y(&s_cal_r, y);

    if((x * x + y * y) < PK_ADC_DEAD_ZONE_SQUA)
    {
        x = 0;
        y = 0;
    }
    if(DEBUG_AXIS) printf(" %d,%d \t\t", x, y);

    if(abs(x - lastXR) > PK_REPORT_THRESHOLD)
    {
        if(abs(x) < TRIMUI_AXIS_RANGE)
            trimui_vaxis(0, ABS_RX, x);
        lastXR = x;
    }

    if(abs(y - lastYR) > PK_REPORT_THRESHOLD)
    {
        if(abs(y) < TRIMUI_AXIS_RANGE)
            trimui_vaxis(0, ABS_RY, y);
        lastYR = y;
    }
    return 0;
}


#define SYSTEM_SUSPEND_FLAG   "/tmp/system_suspend"
static void miyoo_parse_serial_input(const char * cmd, int len)
{
    int i;
    if(access(SYSTEM_SUSPEND_FLAG, F_OK) == 0) return;

    //printf("len=%d, size=%d\n", len, sizeof(s_frame));
    if(len < TRIMUI_PAD_FRAME_LEN)
        return;

    //FIXME: check frame shift finding 0xFF/0xFE, seems no issue now 19200 rate.
    memcpy(&s_frame_l, cmd, sizeof(s_frame_l));
    if(s_frame_l.magic != TM_PLAYER_MAGIC 
      ||s_frame_l.magicEnd != TM_PLAYER_MAGIC_END)
      return;

    s_last_l = s_frame_l;
}


static pthread_t s_ntid_left, s_ntid_right, s_ntid_miyooio;
char s_rcv_buf_l[1024];
//char s_rcv_buf_r[1024];

static void * trimui_poll_thread_joystick(void *arg)
{
    int fd, len;
    fd = trimui_uart_open(MIYOO_NODE_JOYSTICK);
    trimui_uart_set(fd, 9600, 0, 8, 1, 'N');

    while (1)
    {
        len = trimui_uart_recv(fd, s_rcv_buf_l, 99);
        if (len > 0)
        {
            s_rcv_buf_l[len] = '\0';
            //dump_cmd_frame(s_rcv_buf_l, len);
            //trimui_parse_input_left(s_rcv_buf_l, len);
            miyoo_parse_serial_input(s_rcv_buf_l, len);
        }
        else
        {
            printf("cannot receive data\n");
        }
        usleep(16666 / 2);
    }
    trimui_uart_Close(fd);
    return NULL;
}

static void * trimui_poll_thread_miyooio(void *arg)
{
    int fd, len, i;
    fd = open(MIYOO_NODE_IO, O_RDWR);
    trimui_uart_set(fd, 9600, 0, 8, 1, 'N');

    memset(s_io_data, 0, sizeof(s_io_data));
    memset(s_io_data_last, 0, sizeof(s_io_data_last));

    while (1)
    {
        if(s_lock_suspend) 
        {
            usleep(100 * 1000);
            continue;
        }

        read(fd, s_io_data, sizeof(s_io_data));
        
        trimui_do_turbo();

        for (i = 0; i < ARRAY_SIZE(s_tm_map); i++)
        {
            if(key_pressed(s_tm_map[i].keymask))
                trimui_vkey(s_tm_map[i].port, s_tm_map[i].keycode, 1);
            if(key_released(s_tm_map[i].keymask))
                trimui_vkey(s_tm_map[i].port, s_tm_map[i].keycode, 0);
        }
        for (i = 0; i < ARRAY_SIZE(s_tm_map_axis); i++)
        {
            if(key_pressed(s_tm_map_axis[i].keymask))
                trimui_vaxis(s_tm_map_axis[i].port, s_tm_map_axis[i].axis, s_tm_map_axis[i].value);
            if(key_released(s_tm_map_axis[i].keymask))
            {
                if (!axis_hold(s_tm_map_axis[i].axis, s_tm_map_axis, ARRAY_SIZE(s_tm_map_axis)))
                    trimui_vaxis(s_tm_map_axis[i].port, s_tm_map_axis[i].axis, 0);
            }
        }
        memcpy(s_io_data_last, s_io_data, sizeof(s_io_data));
        
        report_axis_lr();

        usleep(16666 / 4);
    }
    trimui_uart_Close(fd);
    return NULL;
}

static void trimui_start_pad_thread()
{
    pthread_create(&s_ntid_left, NULL, trimui_poll_thread_joystick, NULL);
    pthread_create(&s_ntid_right, NULL, trimui_poll_thread_miyooio, NULL);
}

static void check_suspend_lock()
{
    if (access(SYSTEM_SUSPEND_FLAG, F_OK) == 0)
        s_lock_suspend = 1;
    else
        s_lock_suspend = 0;
}

int main(int argc, char **argv)
{
    printf("MIYOO Input Daemon %s\n", __DATE__);
    memset(&s_frame_l, 0, sizeof(s_frame_l));
    memset(&s_last_l,  0, sizeof(s_last_l));

    s_cal_l = pk_read_cal_config(JOYPAD_CONFIG_FILE_LEFT);
    s_cal_r = pk_read_cal_config(JOYPAD_CONFIG_FILE_RIGHT);
    trimui_setup_xpad(0); //player1 only
    trimui_start_pad_thread();
    while (1)
    {
        usleep(1 * 1000 * 1000);
        check_suspend_lock();
        trimui_check_turbo_settting();
        // trimui_check_rotate_settting();
    }

    return 0;
}
