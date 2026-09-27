struct Maybe<T, P> {
    try {
        P ptr;
        
        if (ptr > 0) assert(0);
    } catch {
        T* value: P;
    }
};

struct FreeNode {
    Maybe<FreeNode, u32> left;
    Maybe<FreeNode, u32> right;
    u32 space_offset;
    u32 space_size;
};

struct Value {
    u32 size;
    char content[size];
};

struct DataNode {
    Maybe<DataNode, u32> left;
    Maybe<DataNode, u32> right;
    Maybe<Value, u32> value;
    u32 key_size;
    char key[key_size];
};

struct File {
    u32 magic;
    u16 major;
    u16 minor;
    u32 sections;
    Maybe<FreeNode, u32> free_node_root;
    Maybe<DataNode, u32> data_node_root;
};

File file @ 0x00;