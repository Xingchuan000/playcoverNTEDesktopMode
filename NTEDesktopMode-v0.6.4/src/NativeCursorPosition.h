#pragma once
#include <cmath>
#include <cstdint>
#include <mutex>
namespace NativeCursor {
// FVector2D is two doubles in this build; AAPCS64 returns it in d0/d1.
struct Position { double x,y; };
struct PositionSample { Position value; uint64_t epoch=0; bool valid=false; };
inline bool MapPosition(Position point,Position boundsOrigin,Position boundsSize,Position renderSize,Position &out) {
    if (!std::isfinite(point.x)||!std::isfinite(point.y)||!std::isfinite(boundsOrigin.x)||!std::isfinite(boundsOrigin.y)
        || !std::isfinite(boundsSize.x)||!std::isfinite(boundsSize.y)||!std::isfinite(renderSize.x)||!std::isfinite(renderSize.y)
        || boundsSize.x<=0||boundsSize.y<=0||renderSize.x<1||renderSize.y<1||renderSize.x>65536||renderSize.y>65536) return false;
    double x=(point.x-boundsOrigin.x)*renderSize.x/boundsSize.x;
    double y=(point.y-boundsOrigin.y)*renderSize.y/boundsSize.y;
    if (x<0||y<0||x>=renderSize.x||y>=renderSize.y) return false;
    out={fmin(x,renderSize.x-1),fmin(y,renderSize.y-1)}; return true;
}
class PositionMailbox {
    std::mutex mutex;
    PositionSample sample={};
public:
    void Publish(Position point,uint64_t epoch) {std::lock_guard<std::mutex> lock(mutex); sample={point,epoch,true};}
    void Invalidate() {std::lock_guard<std::mutex> lock(mutex); sample.valid=false;}
    bool Read(uint64_t epoch,Position &out) {
        std::lock_guard<std::mutex> lock(mutex);
        if (!sample.valid || sample.epoch!=epoch) return false;
        out=sample.value; return true;
    }
};
}
