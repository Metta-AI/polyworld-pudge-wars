fdLastDirection = 11
fdTriggerMargin = 0
fdReturnUncertainty = 8
fdContinuationBonus = 15
fdBrakeBonus = 0
holdBack = 16
leadDiv = 30
retreatPct = 40
recoverUntilPct = 90
curveEnabled = 1
dim ids(9)
dim px(9)
dim py(9)
dim hp(9)
dim peak(9)
dim team(9)
dim alive(9)
dim layer(9)
dim shield(9)
dim caught(9)
dim rot(9)
dim sampleX(9)
dim sampleY(9)
dim sampleTick(9)
dim vx(9)
dim vy(9)
dim carried(9)
dim air(9)
dim safe(9)
dim lanes(9)
dim fdMemory(175)
dim fdHeads(439)
dim fdPath(51)
dim fdState(39)
dim bfMemory(319)
dim bfState(31)
dim pfTravel(160)
dim bsState(2)
dim bsPath(19)
dim geo(39)
dim geoCarry(31)
dim ff(191)
sub ffPath(fi,fo,ft,fx,fy,fu,fv,fd,fe,fn,fs,fh,fk)
ff(153)=999
fo=ff(151)
fx=px(fi)*100
fy=py(fi)*100
fh=fx-px(fo)*100
fk=fy-py(fo)*100
fdLength(fh,fk,0,0,0,0)
fn=fdState(39)
if fn<1 then fn=1
fh=fh*100\fn
fk=fk*100\fn
fs=ff(152)
ff(0)=fx
ff(1)=fy
for ft=1 to 48
if ff(153)=999 then
fu=px(fo)*100+vx(fo)*ft*100\8
fv=py(fo)*100+vy(fo)*ft*100\8
if fu<800 then fu=800
if fu>11900 then fu=11900
if fv<800 then fv=800
if fv>11900 then fv=11900
fd=fu-fx
fe=fv-fy
fdLength(fd,fe,0,0,0,0)
if fdState(39)<=fs+100 then
ff(153)=ft
fx=fu+fh*3
fy=fv+fk*3
else
fd=fu+fh-fx
fe=fv+fk-fy
fdLength(fd,fe,0,0,0,0)
fn=fdState(39)
if fn<1 then fn=1
fx=fx+fd*fs\fn
fy=fy+fe*fs\fn
end if
end if
ff(ft*2)=fx
ff(ft*2+1)=fy
next ft
end sub
sub ffContact(fa,fb,fi,ft,fd,fc,fn,fq,fj,fe,fx,fy,fv,fw,fm)
ff(160)=-1
ff(161)=999
ff(162)=2147483647
fn=535+radiusLevel*12
if selfBuff=4 then fn=672+radiusLevel*18
for fj=0 to count-1
if alive(fj)=1 and ids(fj)<>selfId and shield(fj)=0 then
fq=0
if fj=fi then
ft=999
fd=0
fc=0
for fe=8 to 48 step 2
if fe>=ff(161) then exit for
fx=(pfOriginX+fa*ff(98+fe)\100-ff(fe*2))\10
fy=(pfOriginY+fb*ff(98+fe)\100-ff(fe*2+1))\10
fv=(pfOriginX+fa*ff(96+fe)\100-ff(fe*2-4))\10
fw=(pfOriginY+fb*ff(96+fe)\100-ff(fe*2-3))\10
if fe=8 then
fv=(pfOriginX+fa\2-ff(fe*2))\10
fw=(pfOriginY+fb\2-ff(fe*2+1))\10
end if
disk(fv,fw,fx,fy,0,0,fn\10)
if diskHit=1 then
ft=fe
fq=ff(98+fe)\100
fd=ff(98+fe)
exit for
end if
if ff(98+fe)>pfLimit+fn then exit for
next fe
else
fv=vx(fj)*100\8
fw=vy(fj)*100\8
ft=30
for fe=1 to 3
fx=px(fj)*100+fv*ft-pfOriginX
fy=py(fj)*100+fw*ft-pfOriginY
fd=(fx*fa+fy*fb)\100
fc=(fx*fb-fy*fa)\100
fq=fd-fn
if fc>0-fn and fc<fn then
root((fn\10)*(fn\10)-(fc\10)*(fc\10))
fq=fd-rootValue*10
end if
fq=fq\100
if fq<0 then fq=0
if fq>160 then fq=160
ft=pfTravel(fq)
next fe
end if
fm=2147483647
if fq=0 then fm=(fd-110)*(fd-110)+fc*fc
if fc>=0-fn and fc<=fn and fd>0 and fq*100<=pfLimit then
if ft<ff(161) or (ft=ff(161) and fm<ff(162)) then
ff(160)=fj
ff(161)=ft
ff(162)=fm
end if
end if
end if
next fj
end sub
sub ffFinish(fi,fh,fo,ft,fa,fb,fn,fx,fy,fs,fd,fc,fr,fv,fp,fq)
if thrown=1 or hookReady=0 or selfHooked=1 or eliteCastRisk=1 or catchTarget<0 then exit sub
if ff(159)=worldTick then exit sub
ff(159)=worldTick
fi=catchTarget
ff(151)=-1
fo=0
for fh=0 to hookCount()-1
if hookVictim(fh)=ids(fi) and hookTeam(fh)=selfTeam and hookOwner(fh)<>selfId then
fo=hookOwner(fh)
for ft=0 to count-1
if ids(ft)=fo and alive(ft)=1 then ff(151)=ft
next ft
end if
next fh
if ff(151)<0 then exit sub
ff(150)=1
for ft=0 to count-1
if ft<>fi and alive(ft)=1 and caught(ft)=1 then exit sub
next ft
if fo<1 or fo>10 then exit sub
fh=fo*16
if fdMemory(fh+6)<3 then exit sub
fx=(px(ff(151))-px(fi))*100
fy=(py(ff(151))-py(fi))*100
fd=fx*fdMemory(fh+4)+fy*fdMemory(fh+5)
fc=fx*fdMemory(fh+5)-fy*fdMemory(fh+4)
if fc<0 then fc=0-fc
if fd<=0 or fc*2>fd then exit sub
fdLength(fdMemory(fh+4),fdMemory(fh+5),0,0,0,0)
ff(152)=fdState(39)
if ff(152)<75 then ff(152)=75
if ff(152)>180 then ff(152)=180
ffPath(fi,0,0,0,0,0,0,0,0,0,0,0,0)
if ff(153)<=8 then exit sub
pfPrepare(0,0,0,0,0,0,0)
fs=60+speedLevel*3
if selfBuff=5 then fs=fs*2
fd=50
for ft=8 to 48
fs=fs+3
if fs>180 then fs=180
fd=fd+fs
ff(98+ft)=fd
next ft
for ft=8 to 48 step 2
fdLength(ff(ft*2)-pfOriginX,ff(ft*2+1)-pfOriginY,0,0,0,0)
fd=(fdState(39)-350)\100
if fd<0 then fd=0
if fd>160 then fd=160
if pfTravel(fd)<=ft then exit for
next ft
ff(158)=ft
ff(155)=999
for fr=0 to 1
ft=ff(158)+fr*4
if ft<=48 and ft<ff(153) then
fx=ff(ft*2)\100
fy=ff(ft*2+1)\100
fa=fx*100-pfOriginX
fb=fy*100-pfOriginY
fdLength(fa,fb,0,0,0,0)
fn=fdState(39)
if fn>0 then
fa=fa*100\fn
fb=fb*100\fn
pfLimitRay(fa,fb,0,0,0,0,0)
ffContact(fa,fb,fi,0,0,0,0,0,0,0,0,0,0,0,0)
if ff(160)=fi and ff(161)<ff(153) and ff(161)<ff(155) then
ff(155)=ff(161)
ff(156)=fx
ff(157)=fy
end if
end if
end if
next fr
if ff(155)=999 then exit sub
bsLaunch(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
if bsState(0)=1 then exit sub
shotAccepted=hookTo(ff(156),ff(157))
if shotAccepted=1 then
thrown=1
castX=ff(156)
castY=ff(157)
castRecipient=0
print "FINISH_CAST ",worldTick," ",ids(fi)," ",ff(155)," ",ff(153)," ",castX," ",castY
end if
end sub
sub root(n)
rootLo = 0
rootHi = 256
while rootLo + 1 < rootHi
rootMid = (rootLo + rootHi) \ 2
if rootMid * rootMid <= n then
rootLo = rootMid
else
rootHi = rootMid
end if
wend
rootValue = rootLo
end sub
sub disk(ax, ay, bx, by, cx, cy, radius)
diskDx = bx - ax
diskDy = by - ay
diskLen = diskDx * diskDx + diskDy * diskDy
diskX = cx - ax
diskY = cy - ay
diskDot = diskX * diskDx + diskY * diskDy
diskHit = 0
if diskDot <= 0 then
if diskX * diskX + diskY * diskY <= radius * radius then diskHit = 1
elseif diskDot >= diskLen then
diskX = cx - bx
diskY = cy - by
if diskX * diskX + diskY * diskY <= radius * radius then diskHit = 1
else
diskCross = diskX * diskDy - diskY * diskDx
if diskCross * diskCross <= radius * radius * diskLen then diskHit = 1
end if
end sub
sub bsLaunch(bsI, bsK, bsT, bsX, bsY, bsVx, bsVy, bsN, bsNext, bsAx, bsAy, bsBx, bsBy, bsR, bsJ)
if selfLayer <> selfTeam or selfHooked = 1 or blinked = 1 or rescueRequest = 1 or fdState(18) = 0 then exit sub
bsState(1) = fdState(24)
bsState(2) = fdState(25)
bsX = selfX * 100
bsY = selfY * 100
bsVx = fdState(3)
bsVy = fdState(4)
bsPath(0) = bsX
bsPath(1) = bsY
for bsT = 1 to 9
fdLength(bsVx, bsVy, 0, 0, 0, 0)
bsN = fdState(39)
bsNext = bsN - 9
if bsNext < 0 then bsNext = 0
if bsN > 0 then
bsVx = bsVx * bsNext \ bsN
bsVy = bsVy * bsNext \ bsN
end if
bsX = bsX + bsVx
bsY = bsY + bsVy
bsPath(bsT * 2) = bsX
bsPath(bsT * 2 + 1) = bsY
next bsT
for bsI = 1 to 10
bsK = bsI * 40
if fdHeads(bsK + 26) > 0 and fdHeads(bsK + 27) <> selfTeam and fdMemory(bsI * 16 + 6) >= 3 then
bsAx = (fdHeads(bsK) - bsPath(0)) \ 10
bsAy = (fdHeads(bsK + 1) - bsPath(1)) \ 10
for bsT = 1 to 9
if bsT <= fdHeads(bsK + 26) * 2 then
bsJ = (bsT \ 2) * 2
bsX = fdHeads(bsK + bsJ)
bsY = fdHeads(bsK + bsJ + 1)
if bsT mod 2 = 1 then
bsX = (bsX + fdHeads(bsK + bsJ + 2)) \ 2
bsY = (bsY + fdHeads(bsK + bsJ + 3)) \ 2
end if
bsBx = (bsX - bsPath(bsT * 2)) \ 10
bsBy = (bsY - bsPath(bsT * 2 + 1)) \ 10
bsR = (fdHeads(bsK + 29) + 100) \ 10
if fdHeads(bsK + 28) = 0 then bsR = bsR + bsT * fdReturnUncertainty \ 20
disk(bsAx, bsAy, bsBx, bsBy, 0, 0, bsR)
if diskHit = 1 then
bsState(0) = 1
eliteCastRisk = 1
print "BAITER_COAST ", worldTick, " ", bsI, " ", bsT, " ", selfX, " ", selfY, " ", bsState(1), " ", bsState(2)
exit sub
end if
bsAx = bsBx
bsAy = bsBy
end if
next bsT
end if
next bsI
end sub
sub geoExtend(gi, gj, gx, gy, gv, gb, gkind, gdx, gdy, gn, ghx, ghy, gt, gpx, gpy, gfirst)
if blinkReady = 0 or geo(30) = 1 or hookFlying(ownHook) = 0 or hookVictim(ownHook) <> 0 or selfRot = 1 then exit sub
if worldTick-geo(0) < 4 or worldTick mod 4 <> 0 then exit sub
ghx = hookX(ownHook)
ghy = hookY(ownHook)
root((ghx-geo(28))*(ghx-geo(28))+(ghy-geo(29))*(ghy-geo(29)))
geo(32) = reach-rootValue
if geo(32) > 20 or geo(32) < 0 then exit sub
gj = selfId*16
gdx = fdMemory(gj+4)
gdy = fdMemory(gj+5)
fdLength(gdx,gdy,0,0,0,0)
gn = fdState(39)
if gn < 60 then exit sub
gdx = gdx*100\gn
gdy = gdy*100\gn
if (ghx-geo(28))*gdx+(ghy-geo(29))*gdy < 0 then exit sub
gfirst = -1
geo(33) = 10000
for gi = 0 to count-1
if alive(gi) = 1 and ids(gi) <> selfId and shield(gi) = 0 then
root((px(gi)-ghx)*(px(gi)-ghx)+(py(gi)-ghy)*(py(gi)-ghy))
gt = rootValue*100\gn
if gt > 36 then gt = 36
gpx = px(gi)+vx(gi)*gt\8-ghx
gpy = py(gi)+vy(gi)*gt\8-ghy
gv = (gpx*gdx+gpy*gdy)\100
gb = (gpx*gdy-gpy*gdx)\100
if gv > 0 and gv < geo(33) and gv <= geo(32)+18+clearance then
if gb*gb <= clearance*clearance then
geo(33) = gv
gfirst = gi
end if
end if
end if
next gi
if gfirst < 0 then exit sub
if team(gfirst) = selfTeam then exit sub
if geo(33) <= geo(32)-clearance and air(gfirst) = 0 then exit sub
gb = -1000000
for gi = 0 to 2
gx = selfX-18
if selfTeam = 1 then gx = selfX+18
gy = selfY
if gi > 0 then
gx = selfX-13
if selfTeam = 1 then gx = selfX+13
gy = selfY-13
if gi = 2 then gy = selfY+13
end if
if gx < 14 then gx = 14
if gx > 114 then gx = 114
if gy < 16 then gy = 16
if gy > 111 then gy = 111
gv = 0
for gj = 0 to count-1
if alive(gj) = 1 and ids(gj) <> selfId then
gt = (gx-px(gj))*(gx-px(gj))+(gy-py(gj))*(gy-py(gj))
if gt < 36 then gv = -1000000
if team(gj) <> selfTeam and gt < 576 then gv = -1000000
if rot(gj) = 1 and gt < 144 then gv = -1000000
end if
next gj
if (gx-selfX)*(gx-selfX)+(gy-selfY)*(gy-selfY) < 144 then gv = -1000000
if gv = 0 and fdState(18) > 0 then
fdTrajectory(gx,gy,2,0,0,0,0,0,0,0,0,0,0,0,0,0)
fdScore(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
if fdState(10) < 0 then gv = -1000000
end if
gpx = fdState(24)
gpy = fdState(25)
if selfHp*100 < selfMaxHp*80 then
gpx = homeX
gpy = homeY
elseif selfGold >= 6 and selfBuff = 0 then
gpx = 22
if selfTeam = 1 then gpx = 106
gpy = 64
end if
root((gx-gpx)*(gx-gpx)+(gy-gpy)*(gy-gpy))
gv = gv-rootValue
if gv > gb then
gb = gv
geo(34) = gx
geo(35) = gy
end if
next gi
if gb < -1000 then exit sub
if blinkTo(geo(34),geo(35)) = 1 then
rtAfterBlink(0)
geo(30) = 1
geo(36) = worldTick
geo(1) = worldTick-8
print "GEOMETRY_EXTEND ",worldTick," ",originX," ",originY," ",ids(gfirst)," ",geo(32)," ",geo(33)
end if
end sub
sub geoHeal(hi, hx, hy, hj, hh, hd, hv, hs)
geo(27) = -75
if peak(hi)-hp(hi) < 120 or caught(hi) = 1 or layer(hi) <> selfTeam then exit sub
if (px(hi)-hx)*(px(hi)-hx)+(py(hi)-hy)*(py(hi)-hy) > 784 then exit sub
for hj = 0 to count-1
if alive(hj) = 1 and team(hj) <> selfTeam then
hd = (px(hi)-px(hj))*(px(hi)-px(hj))+(py(hi)-py(hj))*(py(hi)-py(hj))
if hd <= 1024 then exit sub
end if
next hj
for hh = 0 to hookCount()-1
if hookTeam(hh) <> selfTeam then
hd = (px(hi)-hookX(hh))*(px(hi)-hookX(hh))+(py(hi)-hookY(hh))*(py(hi)-hookY(hh))
if hd <= 1296 then exit sub
end if
next hh
geo(27) = 35
if hp(hi)*100 < peak(hi)*50 then geo(27) = 50
end sub
sub geoValue(gi, gj, gx, gy, ghx, ghy, gdx, gdy, gn, gt, gpx, gpy, gv, gdot, gcross, gfirst)
gx = fdPath(24) \ 100
gy = fdPath(25) \ 100
ghx = hookX(ownHook)
ghy = hookY(ownHook)
gt = 0
if hookFlying(ownHook) = 1 then
gdx = ghx - geo(6)
gdy = ghy - geo(7)
root(gdx*gdx+gdy*gdy)
gn = rootValue
if gn > 0 and gn < 6 then
ghx = ghx+gdx*12\gn
ghy = ghy+gdy*12\gn
gt = 8
end if
end if
gdx = gx-ghx
gdy = gy-ghy
gn = gdx*gdx+gdy*gdy
geo(12) = 0
if gn = 0 then exit sub
root(gn)
geo(12) = 0-rootValue\5
gfirst = 2147483647
for gi = 0 to count-1
if alive(gi) = 1 and ids(gi) <> selfId and shield(gi) = 0 then
root((px(gi)-ghx)*(px(gi)-ghx)+(py(gi)-ghy)*(py(gi)-ghy))
gj = gt+rootValue*5\9
if gj > 48 then gj = 48
gpx = px(gi)+vx(gi)*gj\8
gpy = py(gi)+vy(gi)*gj\8
gdot = (gpx-ghx)*gdx+(gpy-ghy)*gdy
gcross = (gpx-ghx)*gdy-(gpy-ghy)*gdx
if gdot > 0 and gdot < gn and gdot < gfirst then
if gcross*gcross <= (clearance+1)*(clearance+1)*gn then
gfirst = gdot
gv = -75
if team(gi) <> selfTeam then
gv = 45+(peak(gi)-hp(gi))*30\peak(gi)
if caught(gi) = 1 then gv = 150
else
geoHeal(gi,gx,gy,0,0,0,0,0)
gv = geo(27)
end if
if hookVictim(ownHook) <> 0 then gv = 0
geo(12) = gv-rootValue\5
end if
end if
end if
next gi
if hookVictim(ownHook) <> 0 then
for gi = 0 to count-1
if alive(gi) = 1 and ids(gi) <> selfId then
root((px(gi)-gx)*(px(gi)-gx)+(py(gi)-gy)*(py(gi)-gy))
if team(gi) = selfTeam and rootValue < 20 then
geo(12) = geo(12)+24-rootValue
elseif team(gi) <> selfTeam and ids(gi) <> hookVictim(ownHook) and rootValue < 24 then
geo(12) = geo(12)-2*(24-rootValue)
end if
end if
next gi
end if
if selfHp*100 < selfMaxHp*85 then
root((selfX-homeX)*(selfX-homeX)+(selfY-homeY)*(selfY-homeY))
gv = rootValue
root((gx-homeX)*(gx-homeX)+(gy-homeY)*(gy-homeY))
geo(12) = geo(12)+(gv-rootValue)*2
end if
if selfGold >= 6 and selfBuff = 0 then
gpx = 22
if selfTeam = 1 then gpx = 106
root((selfX-gpx)*(selfX-gpx)+(selfY-64)*(selfY-64))
gv = rootValue
root((gx-gpx)*(gx-gpx)+(gy-64)*(gy-64))
geo(12) = geo(12)+(gv-rootValue)*2
end if
end sub
sub geoContinue(gi, gx, gy, gv, gb, gkind, gdx, gdy, gn, ghx, ghy, gt, gj, gpx, gpy, glimit)
if selfLayer <> selfTeam or selfHooked = 1 or recovering = 1 or attacking = 1 or foreignRot = 1 or ownRescue = 1 or worldTick < rescueUntil then exit sub
if ownHook < 0 then
geo(0) = 0
exit sub
end if
if geo(0) = 0 then
geo(0) = worldTick
geo(1) = worldTick-8
geo(6) = hookX(ownHook)
geo(7) = hookY(ownHook)
geo(28) = geo(6)
geo(29) = geo(7)
geo(30) = 0
end if
geoExtend(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
if geo(36) = worldTick then exit sub
if worldTick-geo(1) >= 8 then
geo(1) = worldTick
gb = -1000000
geo(8) = fdState(24)
geo(9) = fdState(25)
for gi = 0 to 5
gx = selfX
gy = selfY
if gi = 0 then
gx = geo(8)
gy = geo(9)
elseif gi = 1 then
gy = selfY-18
elseif gi = 2 then
gy = selfY+18
elseif gi = 3 then
gx = homeX
gy = homeY
elseif gi = 4 then
gx = 22
if selfTeam = 1 then gx = 106
gy = 64
else
gx = holdX
if target >= 0 then gy = py(target)
end if
if gx < curveMinX then gx = curveMinX
if gx > curveMaxX then gx = curveMaxX
if gy < 16 then gy = 16
if gy > 111 then gy = 111
fdTrajectory(gx,gy,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
gv = 0
if fdState(18) = 1 then
fdScore(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
if fdState(10) < 0 then gv = fdState(10)-1000
end if
geoValue(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
gv = gv+geo(12)
if gi = geo(4) then gv = gv+4
if gv > gb then
gb = gv
geo(2) = gx
geo(3) = gy
geo(5) = gi
end if
next gi
if geo(5) <> geo(4) then print "GEOMETRY_PLAN ",worldTick," ",geo(5)," ",gb," ",hookFlying(ownHook)," ",hookVictim(ownHook)
geo(4) = geo(5)
end if
geo(6) = hookX(ownHook)
geo(7) = hookY(ownHook)
moveTo(geo(2),geo(3))
end sub
sub geoDeliver(gi, gj, gx, gy, gv, gb, gkind, gdx, gdy, gn, ghx, ghy, gt, gpx, gpy, gfirst)
if ownHook < 0 then exit sub
if geoCarry(0) <> hookVictim(ownHook) then
geoCarry(0) = hookVictim(ownHook)
geoCarry(1) = worldTick-4
end if
if worldTick-geoCarry(1) >= 4 then
geoCarry(1) = worldTick
geoCarry(2) = selfX
geoCarry(3) = selfY
geoCarry(4) = 0
ghx = hookX(ownHook)
ghy = hookY(ownHook)
root((ghx-selfX)*(ghx-selfX)+(ghy-selfY)*(ghy-selfY))
geoCarry(5) = rootValue
if geoCarry(5) < 2 then exit sub
geoCarry(6) = 0
for gj = 0 to hookCount()-1
if hookTeam(gj) <> selfTeam then
if (hookX(gj)-ghx)*(hookX(gj)-ghx)+(hookY(gj)-ghy)*(hookY(gj)-ghy) < 2304 then geoCarry(6) = 1
end if
next gj
gb = -1000000
for gi = 0 to 2
gx = selfX
gy = selfY
gkind = 1
if gi > 0 then
gx = selfX+(ghx-selfX)*18\geoCarry(5)
gy = selfY+(ghy-selfY)*18\geoCarry(5)
if gx < curveMinX then gx = curveMinX
if gx > curveMaxX then gx = curveMaxX
if gy < 16 then gy = 16
if gy > 111 then gy = 111
gkind = 0
if gi = 2 then gkind = 2
end if
gv = 0
geoCarry(22) = 0
if gi = 2 and (blinkReady = 0 or selfRot = 1 or geoCarry(6) = 0) then gv = -1000000
for gj = 0 to count-1
if alive(gj) = 1 and team(gj) <> selfTeam then
if (gx-px(gj))*(gx-px(gj))+(gy-py(gj))*(gy-py(gj)) < 400 then gv = -1000000
end if
next gj
if gv = 0 then
fdTrajectory(gx,gy,gkind,0,0,0,0,0,0,0,0,0,0,0,0,0)
if fdState(18) > 0 then
fdScore(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
if fdState(10) < 0 then
geoCarry(22) = 32
if selfHp < 360 then gv = -1000000
end if
end if
end if
if gv = 0 then
geoCarry(10) = ghx*100
geoCarry(11) = ghy*100
gj = selfId*16
fdLength(fdMemory(gj+4),fdMemory(gj+5),0,0,0,0)
geoCarry(20) = fdState(39)
if geoCarry(23) > geoCarry(20) then geoCarry(20) = geoCarry(23)
if geoCarry(20) < 100 then geoCarry(20) = 100
if geoCarry(20) > 180 then geoCarry(20) = 180
for gt = 4 to 24 step 4
gdx = fdPath(gt)-geoCarry(10)
gdy = fdPath(gt+1)-geoCarry(11)
fdLength(gdx,gdy,0,0,0,0)
gn = fdState(39)
geoCarry(12) = fdPath(gt)
geoCarry(13) = fdPath(gt+1)
if gn > geoCarry(20)*4 then
geoCarry(12) = geoCarry(10)+gdx*geoCarry(20)*4\gn
geoCarry(13) = geoCarry(11)+gdy*geoCarry(20)*4\gn
end if
geoCarry(21) = 4
if gn <= geoCarry(20)*4+250 then
geoCarry(21) = (gn-250)\geoCarry(20)+1
if geoCarry(21) < 1 then geoCarry(21) = 1
if geoCarry(21) > 4 then geoCarry(21) = 4
end if
for gj = 0 to hookCount()-1
if hookTeam(gj) <> selfTeam then
gfirst = hookOwner(gj)*40
if gt <= fdHeads(gfirst+26)*2 then
geoCarry(14) = fdHeads(gfirst+gt-4)
geoCarry(15) = fdHeads(gfirst+gt-3)
gpx = fdHeads(gfirst+gt)
gpy = fdHeads(gfirst+gt+1)
else
gfirst = hookOwner(gj)*16
geoCarry(14) = hookX(gj)*100+fdMemory(gfirst+4)*(gt-4)
geoCarry(15) = hookY(gj)*100+fdMemory(gfirst+5)*(gt-4)
gpx = hookX(gj)*100+fdMemory(gfirst+4)*gt
gpy = hookY(gj)*100+fdMemory(gfirst+5)*gt
end if
gpx = geoCarry(14)+(gpx-geoCarry(14))*geoCarry(21)\4
gpy = geoCarry(15)+(gpy-geoCarry(15))*geoCarry(21)\4
disk((geoCarry(10)-geoCarry(14))\100,(geoCarry(11)-geoCarry(15))\100,(geoCarry(12)-gpx)\100,(geoCarry(13)-gpy)\100,0,0,6)
if diskHit = 1 then gv = -1000000
end if
next gj
if gv < 0 then exit for
geoCarry(10) = geoCarry(12)
geoCarry(11) = geoCarry(13)
if gn <= geoCarry(20)*4+250 then
gv = 104-gt-geoCarry(21)
exit for
end if
if geoCarry(20) > 180 then geoCarry(20) = 180
next gt
if gv = 0 then
fdLength(fdPath(24)-geoCarry(10),fdPath(25)-geoCarry(11),0,0,0,0)
gv = 76-fdState(39)\150
end if
end if
gv = gv-geoCarry(22)
if gi = 2 then gv = gv-8
if gv > gb then
gb = gv
geoCarry(2) = gx
geoCarry(3) = gy
geoCarry(4) = gi
end if
next gi
end if
if geoCarry(4) = 2 then
if blinkTo(geoCarry(2),geoCarry(3)) = 1 then
rtAfterBlink(0)
geoCarry(1) = worldTick-4
print "GEOMETRY_DELIVER ",worldTick," ",geoCarry(0)," ",originX," ",originY
exit sub
end if
end if
moveTo(geoCarry(2),geoCarry(3))
end sub
sub throwAt(tx, ty, recipient)
shotAccepted = 0
if thrown = 1 or hookReady = 0 or selfHooked = 1 or eliteCastRisk = 1 then exit sub
if tx < 8 then tx = 8
if tx > 119 then tx = 119
if ty < 8 then ty = 8
if ty > 119 then ty = 119
shotDx = tx - originX
shotDy = ty - originY
root(shotDx * shotDx + shotDy * shotDy)
if rootValue = 0 then exit sub
shotX = tx
shotY = ty
if rootValue > reach then
shotX = originX + shotDx * reach \ rootValue
shotY = originY + shotDy * reach \ rootValue
end if
fountainDx = shotX - originX
fountainDy = shotY - originY
fountainX = 129 - 2 * originX
fountainY = 129 - 2 * originY
fountainLen = fountainDx * fountainDx + fountainDy * fountainDy
fountainDot = fountainX * fountainDx + fountainY * fountainDy
fountainBlocked = 0
if fountainDot <= 0 then
if fountainX * fountainX + fountainY * fountainY <= 49 then fountainBlocked = 1
elseif fountainDot >= 2 * fountainLen then
fountainX = 129 - 2 * shotX
fountainY = 129 - 2 * shotY
if fountainX * fountainX + fountainY * fountainY <= 49 then fountainBlocked = 1
else
fountainCross = fountainX * fountainDy - fountainY * fountainDx
if fountainCross * fountainCross <= 49 * fountainLen then fountainBlocked = 1
end if
if fountainBlocked = 1 then exit sub
for shotI = 0 to count - 1
if alive(shotI) = 1 and team(shotI) = selfTeam and ids(shotI) <> selfId and ids(shotI) <> recipient then
if shield(shotI) = 0 then
disk(originX, originY, shotX, shotY, px(shotI), py(shotI), clearance)
if diskHit = 1 then exit sub
disk(originX, originY, shotX, shotY, px(shotI) + vx(shotI) \ 2, py(shotI) + vy(shotI) \ 2, clearance)
if diskHit = 1 then exit sub
end if
end if
next shotI
bsLaunch(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
if bsState(0) = 1 then exit sub
if rescueRequest = 1 then
shotAccepted = rescueAlly(recipient)
else
shotAccepted = hookTo(tx, ty)
end if
if shotAccepted = 1 then
thrown = 1
castX = tx
castY = ty
castRecipient = recipient
end if
end sub
sub moveTo(mx, my)
if mx < 8 then mx = 8
if mx > 119 then mx = 119
if my < 8 then my = 8
if my > 119 then my = 119
fdState(24) = mx
fdState(25) = my
walkTo(mx, my)
end sub
sub foreignRecoveryMove()
escapeY = 56
if selfY > 64 then escapeY = 72
escapeX = 54
if selfLayer = 1 then escapeX = 74
moveTo(escapeX, escapeY)
end sub
sub curveEnd(cx, cy)
curveScale = 1024
if cx > 0 and selfX + cx > curveMaxX then curveScale = (curveMaxX - selfX) * 1024 \ cx
if cx < 0 and selfX + cx < curveMinX then curveScale = (curveMinX - selfX) * 1024 \ cx
if cy > 0 and selfY + cy > 111 then
curveYScale = (111 - selfY) * 1024 \ cy
if curveYScale < curveScale then curveScale = curveYScale
end if
if cy < 0 and selfY + cy < 16 then
curveYScale = (16 - selfY) * 1024 \ cy
if curveYScale < curveScale then curveScale = curveYScale
end if
curveEndX = selfX + cx * curveScale \ 1024
curveEndY = selfY + cy * curveScale \ 1024
curveStep = (curveEndX - selfX) * (curveEndX - selfX) + (curveEndY - selfY) * (curveEndY - selfY)
end sub
sub fdLength(fdX, fdY, fdA, fdB, fdN, fdSquare)
fdA = fdX
fdB = fdY
if fdA < 0 then fdA = 0 - fdA
if fdB < 0 then fdB = 0 - fdB
fdN = fdA + fdB
if fdN = 0 then
fdState(39) = 0
exit sub
end if
fdSquare = fdX * fdX + fdY * fdY
fdN = (fdN + fdSquare \ fdN) \ 2
fdN = (fdN + fdSquare \ fdN) \ 2
fdState(39) = fdN
end sub
sub fdObserve(fdH, fdId, fdB, fdK, fdX, fdY, fdOwner, fdI, fdDx, fdDy, fdN, fdDt, fdFlying, fdVictim)
fdState(18) = 0
fdState(19) = 0
if fdState(2) = 0 or worldTick <= fdState(2) or selfHooked = 1 then
fdState(0) = selfX
fdState(1) = selfY
fdState(2) = worldTick
fdState(3) = 0
fdState(4) = 0
fdState(24) = selfX
fdState(25) = selfY
elseif worldTick - fdState(2) >= 3 then
fdState(3) = (selfX - fdState(0)) * 100 \ (worldTick - fdState(2))
fdState(4) = (selfY - fdState(1)) * 100 \ (worldTick - fdState(2))
fdState(0) = selfX
fdState(1) = selfY
fdState(2) = worldTick
end if
for fdId = 1 to 10
fdHeads(fdId * 40 + 26) = 0
next fdId
for fdH = 0 to hookCount() - 1
fdId = hookOwner(fdH)
if fdId >= 1 and fdId <= 10 then
fdB = fdId * 16
fdK = fdId * 40
fdX = hookX(fdH)
fdY = hookY(fdH)
fdFlying = hookFlying(fdH)
fdVictim = hookVictim(fdH)
fdOwner = -1
for fdI = 0 to count - 1
if ids(fdI) = fdId and alive(fdI) = 1 then fdOwner = fdI
next fdI
if fdMemory(fdB + 2) <> worldTick - 1 or fdMemory(fdB + 3) <> fdFlying or fdMemory(fdB + 10) <> fdVictim then
fdMemory(fdB + 6) = 0
fdMemory(fdB + 4) = 0
fdMemory(fdB + 5) = 0
fdMemory(fdB + 7) = fdX
fdMemory(fdB + 8) = fdY
fdMemory(fdB + 9) = worldTick
if fdOwner >= 0 then
fdDx = fdX - px(fdOwner)
fdDy = fdY - py(fdOwner)
if fdFlying = 0 then
fdDx = 0 - fdDx
fdDy = 0 - fdDy
end if
fdLength(fdDx, fdDy, 0, 0, 0, 0)
fdN = fdState(39)
if fdN > 0 then
fdMemory(fdB + 4) = fdDx * 120 \ fdN
fdMemory(fdB + 5) = fdDy * 120 \ fdN
end if
end if
else
fdMemory(fdB + 6) = fdMemory(fdB + 6) + 1
fdDt = worldTick - fdMemory(fdB + 9)
if fdDt >= 3 then
fdMemory(fdB + 4) = (fdX - fdMemory(fdB + 7)) * 100 \ fdDt
fdMemory(fdB + 5) = (fdY - fdMemory(fdB + 8)) * 100 \ fdDt
fdMemory(fdB + 7) = fdX
fdMemory(fdB + 8) = fdY
fdMemory(fdB + 9) = worldTick
end if
end if
fdMemory(fdB) = fdX
fdMemory(fdB + 1) = fdY
fdMemory(fdB + 2) = worldTick
fdMemory(fdB + 3) = fdFlying
fdMemory(fdB + 10) = fdVictim
fdHeads(fdK + 27) = hookTeam(fdH)
fdHeads(fdK + 28) = fdFlying
fdHeads(fdK + 31) = fdOwner
fdDx = fdX - selfX
fdDy = fdY - selfY
if fdVictim = 0 and fdDx * fdDx + fdDy * fdDy <= 2500 then
fdHeads(fdK + 26) = 12
fdForecast(fdId, fdB, fdK, fdX * 100, fdY * 100, fdMemory(fdB + 4), fdMemory(fdB + 5), 0, 0, 0, 0, 0, fdOwner, 0, 0)
if hookTeam(fdH) <> selfTeam then fdState(18) = fdState(18) + 1
end if
end if
next fdH
end sub
sub fdForecast(fdId, fdB, fdK, fdX, fdY, fdVx, fdVy, fdSpeed, fdT, fdDx, fdDy, fdN, fdOwner, fdAimX, fdAimY)
fdLength(fdVx, fdVy, 0, 0, 0, 0)
fdSpeed = fdState(39)
if fdSpeed < 50 then fdSpeed = 50
if fdSpeed > 180 then fdSpeed = 180
fdHeads(fdK) = fdX
fdHeads(fdK + 1) = fdY
fdHeads(fdK + 29) = 650
if fdMemory(fdB + 6) < 3 then fdHeads(fdK + 29) = 750
for fdT = 1 to 12
if fdHeads(fdK + 28) = 1 then
fdN = fdSpeed
fdSpeed = fdSpeed + 6
if fdSpeed > 180 then fdSpeed = 180
fdVx = fdVx * fdSpeed \ fdN
fdVy = fdVy * fdSpeed \ fdN
elseif fdOwner >= 0 then
fdAimX = px(fdOwner) * 100 + vx(fdOwner) * fdT * 25
fdAimY = py(fdOwner) * 100 + vy(fdOwner) * fdT * 25
fdDx = fdAimX - fdX
fdDy = fdAimY - fdY
fdLength(fdDx, fdDy, 0, 0, 0, 0)
fdN = fdState(39)
if fdN <= fdSpeed * 2 + 100 then
if fdHeads(fdK + 26) > fdT then fdHeads(fdK + 26) = fdT
end if
if fdN > 0 then
fdVx = fdDx * fdSpeed \ fdN
fdVy = fdDy * fdSpeed \ fdN
end if
end if
fdX = fdX + fdVx * 2
fdY = fdY + fdVy * 2
if fdHeads(fdK + 28) = 1 then
if fdX < 1400 and fdVx < 0 then
fdX = 2800 - fdX
fdVx = 0 - fdVx
elseif fdX > 11500 and fdVx > 0 then
fdX = 23000 - fdX
fdVx = 0 - fdVx
end if
if fdY < 1600 and fdVy < 0 then
fdY = 3200 - fdY
fdVy = 0 - fdVy
elseif fdY > 11200 and fdVy > 0 then
fdY = 22400 - fdY
fdVy = 0 - fdVy
end if
end if
fdHeads(fdK + fdT * 2) = fdX
fdHeads(fdK + fdT * 2 + 1) = fdY
next fdT
end sub
sub fdTrajectory(fdMx, fdMy, fdKind, fdX, fdY, fdVx, fdVy, fdSpeed, fdCap, fdT, fdDx, fdDy, fdN, fdDot, fdCross, fdNext)
fdX = selfX * 100
fdY = selfY * 100
fdVx = fdState(3)
fdVy = fdState(4)
fdCap = 54 + 54 * itemRank(0) * 8 \ 100
if selfBuff = 1 then fdCap = fdCap + 21
if selfRot = 1 or foreignRot = 1 then fdCap = fdCap * 60 \ 100
if fdKind = 2 then
fdX = fdMx * 100
fdY = fdMy * 100
fdVx = 0
fdVy = 0
end if
fdPath(0) = fdX
fdPath(1) = fdY
for fdT = 4 to 24 step 4
fdDx = fdMx * 100 - fdX
fdDy = fdMy * 100 - fdY
if fdKind = 1 or fdKind = 2 then
fdDx = 0
fdDy = 0
end if
if fdKind = 3 and fdT > 8 then
fdDx = selfX * 100 - fdX
fdDy = selfY * 100 - fdY
end if
fdLength(fdDx, fdDy, 0, 0, 0, 0)
fdN = fdState(39)
fdLength(fdVx, fdVy, 0, 0, 0, 0)
fdSpeed = fdState(39)
fdNext = fdCap
if fdN < 180 then fdNext = fdN \ 3
fdDot = fdVx * fdDx + fdVy * fdDy
if fdDot < 0 then fdNext = 0
if fdN = 0 then fdNext = 0
if fdNext > fdSpeed + 28 then fdNext = fdSpeed + 28
if fdNext < fdSpeed - 36 then fdNext = fdSpeed - 36
if fdNext < 0 then fdNext = 0
if fdSpeed = 0 then
if fdN > 0 then
fdVx = fdDx * fdNext \ fdN
fdVy = fdDy * fdNext \ fdN
end if
elseif fdN = 0 then
fdVx = fdVx * fdNext \ fdSpeed
fdVy = fdVy * fdNext \ fdSpeed
else
fdCross = fdVx * fdDy - fdVy * fdDx
fdTurn = 1
if fdCross < 0 then
fdTurn = -1
fdCross = 0 - fdCross
end if
if fdDot > 0 and fdCross * 10 <= fdDot * 58 then
fdVx = fdDx * fdNext \ fdN
fdVy = fdDy * fdNext \ fdN
else
fdOld = fdVx
fdVx = (fdVx * 17 - fdTurn * fdVy * 99) * fdNext \ (fdSpeed * 100)
fdVy = (fdVy * 17 + fdTurn * fdOld * 99) * fdNext \ (fdSpeed * 100)
end if
end if
fdX = fdX + fdVx * 4
fdY = fdY + fdVy * 4
if fdY < 1600 then fdY = 1600
if fdY > 11100 then fdY = 11100
fdLip = 5200
fdN = fdY \ 100 - 64
if fdN > -16 and fdN < 16 then fdLip = 5200 + 600 * (256 - fdN * fdN) \ 256
if selfLayer = 0 then
if fdX > fdLip then
fdX = fdLip
fdVx = 0
end if
if fdX < 1400 then fdX = 1400
else
if fdX < 12800 - fdLip then
fdX = 12800 - fdLip
fdVx = 0
end if
if fdX > 11400 then fdX = 11400
end if
if fdT mod 2 = 0 then
fdPath(fdT) = fdX
fdPath(fdT + 1) = fdY
end if
next fdT
end sub
sub fdScore(fdId, fdK, fdT, fdAx, fdAy, fdBx, fdBy, fdDx, fdDy, fdDot, fdDenom, fdRatio, fdRadius, fdMargin, fdI, fdBodyX)
fdState(10) = 5000
fdState(11) = 24
for fdId = 1 to 10
fdK = fdId * 40
if fdHeads(fdK + 26) > 0 and fdHeads(fdK + 27) <> selfTeam then
for fdT = 2 to fdHeads(fdK + 26) step 2
fdAx = fdHeads(fdK + fdT * 2) - fdPath(fdT * 2)
fdAy = fdHeads(fdK + fdT * 2 + 1) - fdPath(fdT * 2 + 1)
fdRadius = fdHeads(fdK + 29) + 160
if fdHeads(fdK + 28) = 0 then fdRadius = fdRadius + fdT * fdReturnUncertainty
fdMargin = (fdAx * fdAx + fdAy * fdAy - fdRadius * fdRadius) \ 1000
if fdMargin < fdState(10) then fdState(10) = fdMargin
if fdMargin < 0 and fdT * 2 < fdState(11) then fdState(11) = fdT * 2
next fdT
end if
next fdId
for fdI = 0 to count - 1
if ids(fdI) <> selfId and alive(fdI) = 1 and layer(fdI) = selfLayer then
fdBodyX = px(fdI) * 100 + vx(fdI) * 200
fdBodyY = py(fdI) * 100 + vy(fdI) * 200
fdDx = fdPath(16) - fdBodyX
fdDy = fdPath(17) - fdBodyY
fdDenom = fdDx * fdDx + fdDy * fdDy
if fdDenom < 302500 then fdState(10) = fdState(10) - 500
if rot(fdI) = 1 and fdDenom < 1000000 then fdState(10) = fdState(10) - 800
end if
next fdI
end sub
sub fdAvoid(fdDirection, fdMx, fdMy, fdKind, fdScoreValue, fdMinX, fdMaxX)
if fdState(18) = 0 then exit sub
fdTrajectory(fdState(24), fdState(25), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
fdScore(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
fdState(12) = fdState(10)
fdState(13) = fdState(11)
if fdState(12) >= fdTriggerMargin then
if worldTick < fdState(34) then
moveTo(fdState(24), fdState(25))
fdState(19) = 1
end if
exit sub
end if
eliteCastRisk = 1
fdState(14) = -1000000
fdState(15) = selfX
fdState(16) = selfY
fdState(17) = 0
for fdDirection = 0 to fdLastDirection
fdMx = selfX + ((fdDirection mod 3) - 1) * 16
fdMy = selfY + ((fdDirection \ 3) - 1) * 16
fdKind = 0
if fdDirection = 4 then fdKind = 1
if fdDirection = 9 then
fdMx = fdState(24)
fdMy = fdState(25)
elseif fdDirection = 10 then
fdMx = selfX - fdState(4) \ 3
fdMy = selfY + fdState(3) \ 3
elseif fdDirection = 11 then
fdMx = selfX + fdState(4) \ 3
fdMy = selfY - fdState(3) \ 3
elseif fdDirection >= 12 then
fdMx = selfX + ((fdDirection mod 3) - 1) * 16
fdMy = selfY + 16
if fdState(4) > 0 then fdMy = selfY - 16
fdKind = 3
end if
fdMinX = 14
fdMaxX = riverWest - 1
if selfLayer = 1 then
fdMinX = riverEast + 1
fdMaxX = 114
end if
if fdMx < fdMinX then fdMx = fdMinX
if fdMx > fdMaxX then fdMx = fdMaxX
if fdMy < 16 then fdMy = 16
if fdMy > 111 then fdMy = 111
fdTrajectory(fdMx, fdMy, fdKind, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
fdScore(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
fdScoreValue = fdState(10)
if fdScoreValue > 1000 then fdScoreValue = 1000
if fdDirection = 9 then fdScoreValue = fdScoreValue + fdContinuationBonus
if fdDirection = 4 then fdScoreValue = fdScoreValue + fdBrakeBonus
if fdKind = 3 then fdScoreValue = fdScoreValue - 20
if fdScoreValue > fdState(14) then
fdState(14) = fdScoreValue
fdState(15) = fdMx
fdState(16) = fdMy
fdState(17) = fdKind
end if
next fdDirection
if blinkReady = 1 and fdState(14) < -80 and fdState(13) <= 10 then
for fdDirection = 0 to 8
if fdDirection <> 4 then
fdMx = selfX + ((fdDirection mod 3) - 1) * 13
fdMy = selfY + ((fdDirection \ 3) - 1) * 13
if fdMx < fdMinX then fdMx = fdMinX
if fdMx > fdMaxX then fdMx = fdMaxX
if fdMy < 16 then fdMy = 16
if fdMy > 111 then fdMy = 111
fdTrajectory(fdMx, fdMy, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
fdScore(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
if fdState(10) > fdState(14) + 100 then
fdState(14) = fdState(10)
fdState(15) = fdMx
fdState(16) = fdMy
fdState(17) = 2
end if
end if
next fdDirection
end if
if selfRot = 1 then rotToggle()
if fdState(17) = 2 then
if (fdState(15) - selfX) * (fdState(15) - selfX) + (fdState(16) - selfY) * (fdState(16) - selfY) >= 36 then
fdState(20) = blinkTo(fdState(15), fdState(16))
if fdState(20) = 1 then rtAfterBlink(0)
end if
end if
moveTo(fdState(15), fdState(16))
fdState(34) = worldTick + 6
fdState(19) = 1
end sub
sub bfObserve(bi, bb, bd, bx, by, bh, bn, bs, bc, bt, bv, bw)
for bi = 0 to count - 1
bb = bi * 32
if bfMemory(bb + 31) <> ids(bi) or alive(bi) = 0 or worldTick - bfMemory(bb + 2) > 2 then
for bd = 0 to 30
bfMemory(bb + bd) = 0
next bd
bfMemory(bb + 31) = ids(bi)
bfMemory(bb + 10) = px(bi)
bfMemory(bb + 11) = py(bi)
for bd = 24 to 29
bfMemory(bb + bd) = 2
next bd
end if
if alive(bi) = 1 and team(bi) <> selfTeam then
bx = px(bi) - bfMemory(bb)
by = py(bi) - bfMemory(bb + 1)
if bfMemory(bb + 2) > 0 and bx * bx + by * by > 49 then
bfMemory(bb + 7) = worldTick
bfMemory(bb + 8) = px(bi)
bfMemory(bb + 9) = py(bi)
bfMemory(bb + 12) = 0
bfMemory(bb + 13) = 0
bfState(22) = bfState(22) + 1
end if
if caught(bi) = 1 or bfMemory(bb + 18) = 1 then
bfMemory(bb + 12) = 0
bfMemory(bb + 13) = 0
else
bfMemory(bb + 12) = bfMemory(bb + 12) + 1
end if
if bfMemory(bb + 12) = 1 then
bfMemory(bb + 5) = px(bi)
bfMemory(bb + 6) = py(bi)
bfMemory(bb + 3) = 0
bfMemory(bb + 4) = 0
elseif bfMemory(bb + 12) mod 4 = 1 then
bfMemory(bb + 3) = px(bi) - bfMemory(bb + 5)
bfMemory(bb + 4) = py(bi) - bfMemory(bb + 6)
bfMemory(bb + 5) = px(bi)
bfMemory(bb + 6) = py(bi)
end if
if bfMemory(bb + 12) > 24 and worldTick mod 16 = 0 then
bfMemory(bb + 10) = (bfMemory(bb + 10) * 7 + px(bi)) \ 8
bfMemory(bb + 11) = (bfMemory(bb + 11) * 7 + py(bi)) \ 8
end if
bn = 0
bs = 785
for bh = 0 to hookCount() - 1
if hookTeam(bh) = selfTeam and hookVictim(bh) = 0 then
bd = (hookX(bh) - px(bi)) * (hookX(bh) - px(bi)) + (hookY(bh) - py(bi)) * (hookY(bh) - py(bi))
if bd < bs then
bs = bd
bn = hookOwner(bh)
end if
end if
next bh
if bn = 0 then bfMemory(bb + 17) = 0
if bn > 0 and bn <> bfMemory(bb + 17) and bfMemory(bb + 12) >= 5 then
bfMemory(bb + 17) = bn
bfMemory(bb + 13) = worldTick
bfMemory(bb + 15) = px(bi)
bfMemory(bb + 16) = py(bi)
bfMemory(bb + 19) = bfMemory(bb + 3)
bfMemory(bb + 20) = bfMemory(bb + 4)
end if
if bfMemory(bb + 13) > 0 and worldTick - bfMemory(bb + 13) >= 8 and bfMemory(bb + 12) >= 9 then
bx = px(bi) - bfMemory(bb + 15)
by = py(bi) - bfMemory(bb + 16)
bv = bfMemory(bb + 19)
bw = bfMemory(bb + 20)
bc = 0
bt = bx * bv + by * bw
if bx * bx + by * by < 4 then
bc = 1
elseif bt < -2 then
bc = 2
elseif bx * bw - by * bv > 3 then
bc = 3
elseif bx * bw - by * bv < -3 then
bc = 4
elseif bv * bv + bw * bw < 2 then
bc = 5
end if
for bd = 24 to 29
bfMemory(bb + bd) = 1 + bfMemory(bb + bd) * 3 \ 4
next bd
bfMemory(bb + 24 + bc) = bfMemory(bb + 24 + bc) + 4
bfMemory(bb + 14) = bc
bfMemory(bb + 13) = 0
bfState(23) = bfState(23) + 1
end if
end if
bfMemory(bb) = px(bi)
bfMemory(bb + 1) = py(bi)
bfMemory(bb + 2) = worldTick
if alive(bi) = 0 then bfMemory(bb + 2) = 0
bfMemory(bb + 18) = caught(bi)
next bi
end sub
sub bfPressure(bh, bd, bb)
bfState(0) = 0
bfState(1) = 0
bfState(2) = 785
if target < 0 then exit sub
for bh = 0 to hookCount() - 1
if hookTeam(bh) = selfTeam and hookOwner(bh) <> selfId and hookVictim(bh) = 0 and hookFlying(bh) = 1 then
bd = (hookX(bh) - px(target)) * (hookX(bh) - px(target)) + (hookY(bh) - py(target)) * (hookY(bh) - py(target))
if bd < bfState(2) then
bfState(0) = hookOwner(bh)
bfState(1) = bh
bfState(2) = bd
end if
end if
next bh
if bfState(0) = 0 then bfState(3) = 0
bb = target * 32
if bfState(0) > 0 and bfState(0) <> bfState(3) then
bfState(3) = bfState(0)
if bfState(15) = 0 or worldTick - bfState(15) >= 48 then
bfState(4) = worldTick
bfState(15) = worldTick
end if
end if
end sub
sub rtAfterBlink(rtObject)
for rtObject = 0 to objectCount() - 1
if objectId(rtObject) = selfId then
selfObject = rtObject
originX = objectX(rtObject)
originY = objectY(rtObject)
end if
next rtObject
fdState(0) = originX
fdState(1) = originY
fdState(2) = worldTick
fdState(3) = 0
fdState(4) = 0
px(me) = originX
py(me) = originY
sampleX(me) = originX
sampleY(me) = originY
sampleTick(me) = worldTick
vx(me) = 0
vy(me) = 0
end sub
sub pfPrepare(pt, pd, ps, pxv, pyv, pn, pk)
pfOriginX = originX * 100
pfOriginY = originY * 100
pxv = fdState(3)
pyv = fdState(4)
for pt = 1 to 8
fdLength(pxv, pyv, 0, 0, 0, 0)
pn = fdState(39)
pk = pn - 9
if pk < 0 then pk = 0
if pn > 0 then
pxv = pxv * pk \ pn
pyv = pyv * pk \ pn
end if
pfOriginX = pfOriginX + pxv
pfOriginY = pfOriginY + pyv
next pt
if rtTravelReady = 1 and rtTravelSpeed = speedLevel and rtTravelBuff = selfBuff then exit sub
rtTravelReady = 1
rtTravelSpeed = speedLevel
rtTravelBuff = selfBuff
pd = 0
ps = 60 + speedLevel * 3
if selfBuff = 5 then ps = ps * 2
pt = 8
for pk = 0 to 160
while pd < pk * 100
pt = pt + 1
ps = ps + 3
if ps > 180 then ps = 180
pd = pd + ps
wend
pfTravel(pk) = pt
next pk
end sub
sub pfLimitRay(pa, pb, po, pxv, pyv, pd, pc)
pfLimit = reach * 100
if pa > 0 then
pd = (11400 - pfOriginX) * 100 \ pa
if pd < pfLimit then pfLimit = pd
elseif pa < 0 then
pd = (1400 - pfOriginX) * 100 \ pa
if pd < pfLimit then pfLimit = pd
end if
if pb > 0 then
pd = (11100 - pfOriginY) * 100 \ pb
if pd < pfLimit then pfLimit = pd
elseif pb < 0 then
pd = (1600 - pfOriginY) * 100 \ pb
if pd < pfLimit then pfLimit = pd
end if
for po = -1 to objectCount() - 1
pd = 0
if po = -1 then
pxv = 6450 - pfOriginX
pyv = 6450 - pfOriginY
pd = 500
else
if objectKind(po) = 2 then
pxv = objectX(po) * 100 - pfOriginX
pyv = objectY(po) * 100 - pfOriginY
pd = 400
end if
end if
if pd > 0 then
pc = (pxv * pb - pyv * pa) \ 100
if pc * pc < pd * pd then
root((pd \ 10) * (pd \ 10) - (pc \ 10) * (pc \ 10))
pd = (pxv * pa + pyv * pb) \ 100 - rootValue * 10
if pd > 0 and pd < pfLimit then pfLimit = pd
end if
end if
next po
end sub
sub pfContact(pa, pb, pi, pr, pv, pw, pt, pd, pc, pn, pq, pj, pe, pxv, pyv, pm)
pfValue = 0
pfFirst = 999
pn = 535 + radiusLevel * 12
if selfBuff = 4 then pn = 672 + radiusLevel * 18
for pj = 0 to count - 1
if alive(pj) = 1 and ids(pj) <> selfId and shield(pj) = 0 then
pv = vx(pj) * 100 \ 8
pw = vy(pj) * 100 \ 8
if pj = pi then
pv = bfMemory(pi * 32 + 3) * 25
pw = bfMemory(pi * 32 + 4) * 25
if pr = 1 then
pv = 0
pw = 0
elseif pr = 2 then
pv = 0 - pv
pw = 0 - pw
end if
end if
pt = 30
for pe = 1 to 3
pxv = px(pj) * 100 + pv * pt - pfOriginX
pyv = py(pj) * 100 + pw * pt - pfOriginY
pd = (pxv * pa + pyv * pb) \ 100
pc = (pxv * pb - pyv * pa) \ 100
pq = pd - pn
if pc * pc < pn * pn then
root((pn \ 10) * (pn \ 10) - (pc \ 10) * (pc \ 10))
pq = pd - rootValue * 10
end if
pq = pq \ 100
if pq < 0 then pq = 0
if pq > 160 then pq = 160
pt = pfTravel(pq)
next pe
if pc * pc <= pn * pn and pd > 0 and pq * 100 <= pfLimit and pt < pfFirst then
pfFirst = pt
pfValue = 28
if pj = pi then pfValue = 36
if hp(pj) <= 300 + upgradeLevel(0) * 15 then pfValue = pfValue + 12
if team(pj) = selfTeam then
pfValue = -30
if hp(pj) * 100 < peak(pj) * 70 then pfValue = -8
end if
end if
end if
next pj
end sub
sub bfPackets(bb, bh, bx, by, bv, bw, bc, br, bt, bs, be, bm, bn, bp, bq, bk)
bfState(5) = 0
if thrown = 1 or hookReady = 0 or selfHooked = 1 or recovering = 1 or eliteCastRisk = 1 then exit sub
bb = target * 32
if bfMemory(bb + 12) < 5 then exit sub
bfPressure(0, 0, 0)
pfPrepare(0, 0, 0, 0, 0, 0, 0)
bv = bfMemory(bb + 3)
bw = bfMemory(bb + 4)
if bv * bv + bw * bw > 25 then exit sub
bm = -100000
bk = 0
for bc = 0 to 5
bx = px(target) + bv * spanX \ ((leadDiv + speedLevel) \ 2)
by = py(target) + bw * spanX \ ((leadDiv + speedLevel) \ 2)
bn = 1
if ((worldTick \ 64) + selfId) mod 2 = 0 then bn = -1
if bc = 1 or bc = 3 then
by = by - 6
bn = 1
elseif bc = 2 or bc = 4 then
by = by + 6
bn = -1
elseif bc = 5 then
bx = px(target)
by = py(target)
end if
bp = bx * 100 - pfOriginX
bq = by * 100 - pfOriginY
fdLength(bp, bq, 0, 0, 0, 0)
bh = fdState(39)
if bh < 1 then bh = 1
bp = bp * 100 \ bh
bq = bq * 100 \ bh
pfLimitRay(bp, bq, 0, 0, 0, 0, 0)
bt = 0
be = 1000
for br = 0 to 2
pfContact(bp, bq, target, br, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
bs = pfValue
if bs < be then be = bs
bt = bt + bs * bfMemory(bb + 24 + br)
next br
bt = bt + be * 2
if bc = 0 then bt = bt + 15
if bc = 3 or bc = 4 then
bt = bt - 45
if bfState(0) = 0 or worldTick - bfState(4) >= 4 then bt = -100000
if bfState(0) > 0 and bfState(2) < 400 then bt = bt + 80
end if
if bt > bm then
bm = bt
bk = bc
bfState(6) = bx
bfState(7) = by
bfState(12) = bn
end if
next bc
if bk = 3 or bk = 4 then
bfState(5) = 1
bfState(13) = worldTick + 1
bfState(20) = bfState(20) + 1
exit sub
end if
throwAt(bfState(6), bfState(7), 0)
if shotAccepted = 1 then
bfState(8) = worldTick + 160
bfState(9) = bfState(12)
bfState(10) = ids(target)
bfState(13) = worldTick + 16
bfState(21) = bfState(21) + 1
print "PLANNER_PACKET ", worldTick, " ", ids(target), " ", bk, " ", bm
end if
end sub
sub bfContinue(bh, bd, bx, by)
bfState(14) = 0
if worldTick > bfState(13) or bfState(13) = 0 then exit sub
if selfLayer <> selfTeam or recovering = 1 or selfHooked = 1 or foreignRot = 1 or ownRescue = 1 or attacking = 1 then exit sub
if selfHp * 100 < selfMaxHp * 65 then exit sub
for bh = 0 to hookCount() - 1
if hookTeam(bh) <> selfTeam and hookVictim(bh) = 0 then
bd = (hookX(bh) - selfX) * (hookX(bh) - selfX) + (hookY(bh) - selfY) * (hookY(bh) - selfY)
if bd < 900 then exit sub
end if
next bh
bx = selfX
by = selfY + bfState(12) * 8
if by < 20 then by = 20
if by > 108 then by = 108
moveTo(bx, by)
curveActive = 0
bfState(14) = 1
end sub
if worldTick < previousTick or (selfShield > 0 and previousShield = 0) then
count = 0
for i = 0 to 31
bfState(i) = 0
next i
for i = 0 to 319
bfMemory(i) = 0
next i
recovering = 0
rescueUntil = 0
curveActive = 0
dodgeSide = 0
lastSeen = 0
end if
previousTick = worldTick
previousShield = selfShield
if selfHp <= 0 then
curveActive = 0
recovering = 0
end
end if
if selfShield > 0 then
for graceHook = 0 to hookCount() - 1
if hookTeam(graceHook) <> selfTeam and hookVictim(graceHook) = 0 then
graceD2 = (hookX(graceHook) - selfX) * (hookX(graceHook) - selfX) + (hookY(graceHook) - selfY) * (hookY(graceHook) - selfY)
if graceD2 < 1024 then end
end if
next graceHook
end if
for i = 0 to count - 1
alive(i) = 0
carried(i) = 0
air(i) = 0
next i
for obj = 0 to objectCount() - 1
if objectKind(obj) = 1 then
oid = objectId(obj)
slot = -1
for i = 0 to count - 1
if ids(i) = oid then slot = i
next i
if slot < 0 and count < 10 then
slot = count
count = count + 1
ids(slot) = oid
peak(slot) = 1200
sampleTick(slot) = -1
vx(slot) = 0
vy(slot) = 0
carried(slot) = 0
air(slot) = 0
end if
if slot >= 0 then
px(slot) = objectX(obj)
py(slot) = objectY(obj)
hp(slot) = objectHp(obj)
if hp(slot) > peak(slot) then peak(slot) = hp(slot)
team(slot) = objectTeam(obj)
alive(slot) = objectAlive(obj)
layer(slot) = objectLayer(obj)
shield(slot) = objectShielded(obj)
caught(slot) = objectHooked(obj)
rot(slot) = objectRot(obj)
if sampleTick(slot) < 0 or worldTick - sampleTick(slot) > 96 or alive(slot) = 0 then
sampleX(slot) = px(slot)
sampleY(slot) = py(slot)
sampleTick(slot) = worldTick
vx(slot) = 0
vy(slot) = 0
elseif worldTick - sampleTick(slot) >= 8 then
vx(slot) = (px(slot) - sampleX(slot)) * 8 \ (worldTick - sampleTick(slot))
vy(slot) = (py(slot) - sampleY(slot)) * 8 \ (worldTick - sampleTick(slot))
sampleX(slot) = px(slot)
sampleY(slot) = py(slot)
sampleTick(slot) = worldTick
end if
if oid = selfId then
me = slot
selfObject = obj
end if
end if
end if
next obj
peak(me) = selfMaxHp
if selfHp * 100 >= selfMaxHp * recoverUntilPct then recovering = 0
if selfHp * 100 < selfMaxHp * retreatPct then recovering = 1
foreignRecovery = 0
if recovering = 1 and selfLayer <> selfTeam and selfLayer <> 2 then foreignRecovery = 1
if foreignRecovery = 1 then attackTarget(0)
target = -1
targetD2 = 2147483647
catchTarget = -1
catchD2 = 2147483647
swimmer = -1
swimmerD2 = 2147483647
foreignRot = 0
rank = 0
teamCount = 0
for i = 0 to count - 1
if team(i) = selfTeam then
teamCount = teamCount + 1
if ids(i) < selfId then rank = rank + 1
end if
if alive(i) = 1 then
d2 = (px(i) - selfX) * (px(i) - selfX) + (py(i) - selfY) * (py(i) - selfY)
if ids(i) <> selfId and rot(i) = 1 and d2 <= 64 then foreignRot = 1
if team(i) <> selfTeam and shield(i) = 0 then
if d2 < targetD2 then
target = i
targetD2 = d2
end if
if caught(i) = 1 and d2 < catchD2 then
catchTarget = i
catchD2 = d2
end if
if layer(i) = 2 and d2 < swimmerD2 then
swimmer = i
swimmerD2 = d2
end if
end if
end if
next i
if target >= 0 then
lastSeen = worldTick
lastX = px(target)
lastY = py(target)
lastVx = vx(target)
lastVy = vy(target)
end if
threat = -1
threatX = -1
threatY = -1
threatD2 = 485
ownHook = -1
ownRescue = 0
for h = 0 to hookCount() - 1
for i = 0 to count - 1
if hookOwner(h) = ids(i) then air(i) = 1
if hookVictim(h) = ids(i) then carried(i) = hookTeam(h) + 1
next i
if hookOwner(h) = selfId then
ownHook = h
for i = 0 to count - 1
if team(i) = selfTeam and hookVictim(h) = ids(i) then ownRescue = 1
next i
end if
if hookTeam(h) <> selfTeam and (hookFlying(h) = 1 or hookVictim(h) = 0) then
d2 = (hookX(h) - selfX) * (hookX(h) - selfX) + (hookY(h) - selfY) * (hookY(h) - selfY)
if d2 < threatD2 then
threatD2 = d2
threat = h
threatX = hookX(h)
threatY = hookY(h)
end if
end if
next h
bfObserve(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
eliteCastRisk = 0
bsState(0) = 0
if ownHook < 0 then
geoCarry(23) = 0
elseif hookFlying(ownHook) = 1 then
fdLength(fdMemory(selfId*16+4),fdMemory(selfId*16+5),0,0,0,0)
if fdState(39) > geoCarry(23) then geoCarry(23) = fdState(39)
end if
fdObserve(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
if selfHooked = 0 and selfLayer <> 2 and foreignRecovery = 0 then
fdAvoid(0, 0, 0, 0, 0, 0, 0)
if fdState(19) = 1 then end
end if
threat = -1
brawl = 0
if target >= 0 then
if selfHp + 200 >= hp(target) or hp(target) <= 120 or (selfLayer <> selfTeam and selfLayer <> 2) then brawl = 1
end if
wantRot = 0
if targetD2 <= 64 and brawl = 1 and selfLayer <> 2 and recovering = 0 and selfHp > 96 then wantRot = 1
if wantRot <> selfRot then rotToggle()
fleeRot = 0
if foreignRot = 1 and wantRot = 0 then fleeRot = 1
left = selfPoints
while left > 0
purchased = buyUpgrade(1)
if purchased = 0 then purchased = buyUpgrade(2)
if purchased = 0 then purchased = buyUpgrade(0)
if purchased = 0 then purchased = buyUpgrade(3)
if purchased = 0 then
left = 0
else
left = left - 1
end if
wend
if selfInShop = 1 then
buyPower(9)
if selfBuff = 0 then buyPower(3)
if selfHp * 100 < selfMaxHp * 80 then buyPower(0)
buying = 1
while buying = 1
buying = 0
if itemRank(1) < 5 then buying = buyPower(6)
if itemRank(0) < 5 then
if buyPower(5) = 1 then buying = 1
end if
wend
if itemRank(1) > 0 and selfBuff = 0 then buyPower(3)
end if
distanceLevel = upgradeLevel(1)
speedLevel = upgradeLevel(2)
radiusLevel = upgradeLevel(3)
reach = 60 + 4 * distanceLevel
clearance = 6 + (radiusLevel + 7) \ 8
if selfBuff = 4 then
reach = reach * 3 \ 2
clearance = 8 + (radiusLevel * 3 + 15) \ 16
end if
holdX = riverWest - holdBack
curveMinX = 8
curveMaxX = riverWest - 1
if selfTeam = 1 then
holdX = riverEast + holdBack
curveMinX = riverEast + 1
curveMaxX = 119
end if
originX = selfX
originY = selfY
thrown = 0
blinked = 0
attacking = 0
castRecipient = 0
rescueRequest = 0
free = 0
if selfLayer = selfTeam and selfHooked = 0 and recovering = 0 and threat < 0 and fleeRot = 0 then free = 1
if free = 1 and ownRescue = 1 then
geoDeliver(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
end
end if
if free = 1 and worldTick < rescueUntil then
curveActive = 0
walkTo(selfX, selfY)
end
end if
if free = 1 and foreignRot = 0 and hookReady = 1 then
for i = 0 to count - 1
if alive(i) = 1 and team(i) = selfTeam and ids(i) <> selfId then
if allyNeedsRescue(ids(i)) = 1 then
rescueRequest = 1
throwAt(px(i), py(i), ids(i))
rescueRequest = 0
if shotAccepted = 1 then
rescueUntil = worldTick + 12
curveActive = 0
walkTo(selfX, selfY)
if saidMood <> 1 then print "pulling you out"
saidMood = 1
end
end if
end if
end if
next i
end if
if selfHooked = 1 then
curveActive = 0
end
end if
if blinkReady = 1 then
blinkX = selfX
blinkY = selfY
crossing = 0
if selfLayer = 2 then
blinkX = riverWest
if selfTeam = 1 then blinkX = riverEast
elseif selfLayer <> selfTeam and selfY >= 56 and selfY <= 72 and (recovering = 1 or targetD2 > 144) then
half = 11 - 6 * (256 - (selfY - 64) * (selfY - 64)) \ 256
blinkX = 64 - half - 2
if selfTeam = 1 then blinkX = 64 + half + 2
crossing = 1
elseif threat >= 0 then
blinkX = selfX - 14
if selfLayer = 1 then blinkX = selfX + 14
blinkY = selfY + 14 * dodgeSide
end if
if blinkX < 8 then blinkX = 8
if blinkX > 119 then blinkX = 119
if blinkY < 8 then blinkY = 8
if blinkY > 119 then blinkY = 119
if crossing = 1 then
blinkBlocked = 0
if (blinkX - selfX) * (blinkX - selfX) + (blinkY - selfY) * (blinkY - selfY) > 400 then blinkBlocked = 1
for i = 0 to count - 1
if alive(i) = 1 and ids(i) <> selfId then
if rot(i) = 1 and (px(i) - blinkX) * (px(i) - blinkX) + (py(i) - blinkY) * (py(i) - blinkY) <= 144 then blinkBlocked = 1
if layer(i) <> selfLayer then
disk(selfX, selfY, blinkX, blinkY, px(i), py(i), 4)
if diskHit = 1 then blinkBlocked = 1
end if
end if
next i
for obj = 0 to objectCount() - 1
if objectKind(obj) = 2 then
disk(selfX, selfY, blinkX, blinkY, objectX(obj), objectY(obj), 4)
if diskHit = 1 then blinkBlocked = 1
end if
next obj
if blinkBlocked = 1 then
blinkX = selfX
blinkY = selfY
end if
end if
if blinkX <> selfX or blinkY <> selfY then
blinked = blinkTo(blinkX, blinkY)
if blinked = 1 then
rtAfterBlink(0)
end if
end if
end if
if free = 1 and foreignRot = 0 and hookReady = 1 then
pairAlly = -1
pairEnemy = -1
pairHp = 100001
pairDistance = 2147483647
for i = 0 to count - 1
if alive(i) = 1 and team(i) = selfTeam and ids(i) <> selfId and shield(i) = 0 and caught(i) = 0 then
for j = 0 to count - 1
if alive(j) = 1 and team(j) <> selfTeam and shield(j) = 0 and caught(j) = 0 and layer(i) = layer(j) then
d2 = (px(i) - px(j)) * (px(i) - px(j)) + (py(i) - py(j)) * (py(i) - py(j))
midX = (px(i) + px(j)) \ 2
midY = (py(i) + py(j)) \ 2
aimD2 = (midX - selfX) * (midX - selfX) + (midY - selfY) * (midY - selfY)
allyD2 = (px(i) - selfX) * (px(i) - selfX) + (py(i) - selfY) * (py(i) - selfY)
fraction = hp(i) * 1000 \ peak(i)
if d2 <= 30 and aimD2 <= reach * reach then
if fraction < pairHp or (fraction = pairHp and allyD2 < pairDistance) then
pairAlly = i
pairEnemy = j
pairHp = fraction
pairDistance = allyD2
end if
end if
end if
next j
end if
next i
if pairAlly >= 0 then throwAt((px(pairAlly) + px(pairEnemy)) \ 2, (py(pairAlly) + py(pairEnemy)) \ 2, ids(pairAlly))
end if
ff(150)=0
if catchTarget>=0 and catchTarget=target then ffFinish(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
if target >= 0 and targetD2 <= 400 and selfLayer <> 2 and (ff(150)=0 or target<>catchTarget) then throwAt(px(target), py(target), 0)
if catchTarget >= 0 and ff(150)=0 then ffFinish(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
if catchTarget >= 0 and ff(150)=0 then
reeler = catchTarget
for h = 0 to hookCount() - 1
if hookVictim(h) = ids(catchTarget) then
for i = 0 to count - 1
if ids(i) = hookOwner(h) then reeler = i
next i
end if
next h
throwAt((px(catchTarget) + px(reeler)) \ 2, (py(catchTarget) + py(reeler)) \ 2, 0)
end if
if threat >= 0 and threatD2 <= 196 then throwAt(hookX(threat), hookY(threat), 0)
if swimmer >= 0 and (ff(150)=0 or swimmer<>catchTarget) then throwAt(px(swimmer), py(swimmer), 0)
if free = 1 and foreignRot = 0 and catchTarget < 0 and swimmer < 0 and thrown = 0 and hookReady = 1 then
for i = 0 to count - 1
safe(i) = 0
if alive(i) = 1 and team(i) = selfTeam and layer(i) = selfTeam and caught(i) = 0 and shield(i) = 0 and rot(i) = 0 and carried(i) = 0 then
safe(i) = 1
for j = 0 to count - 1
if alive(j) = 1 and team(j) <> selfTeam then
d2 = (px(i) - px(j)) * (px(i) - px(j)) + (py(i) - py(j)) * (py(i) - py(j))
if d2 <= 784 then safe(i) = 0
end if
next j
for h = 0 to hookCount() - 1
if hookTeam(h) <> selfTeam then
d2 = (px(i) - hookX(h)) * (px(i) - hookX(h)) + (py(i) - hookY(h)) * (py(i) - hookY(h))
if d2 <= 784 then safe(i) = 0
end if
next h
end if
next i
healer = -1
recipient = -1
healHp = 100001
healD2 = 2147483647
for i = 0 to count - 1
if safe(i) = 1 and peak(i) - hp(i) >= 120 then
for j = 0 to count - 1
if j <> i and safe(j) = 1 and air(j) = 0 and hp(j) * 100 >= peak(j) * 60 then
d2 = (px(i) - px(j)) * (px(i) - px(j)) + (py(i) - py(j)) * (py(i) - py(j))
forward = px(j) - px(i)
if selfTeam = 1 then forward = 0 - forward
fraction = hp(i) * 1000 \ peak(i)
if d2 >= 16 and d2 <= 576 and forward <= 4 then
if fraction < healHp or (fraction = healHp and d2 < healD2) then
healer = j
recipient = i
healHp = fraction
healD2 = d2
end if
end if
end if
next j
end if
next i
if healer = me then
throwAt(px(recipient), py(recipient), ids(recipient))
if shotAccepted = 1 then
rescueUntil = worldTick + 12
curveActive = 0
walkTo(selfX, selfY)
end
end if
end if
end if
if target >= 0 and (ff(150)=0 or target<>catchTarget) and (targetD2 <= (reach + clearance) * (reach + clearance) or (blinkReady = 1 and targetD2 <= (reach + 18) * (reach + 18))) then
spanX = px(target) - selfX
if spanX < 0 then spanX = 0 - spanX
spanY = py(target) - selfY
if spanY < 0 then spanY = 0 - spanY
if spanY > spanX then spanX = spanY
bfPackets(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
if bfState(5) = 0 then
throwAt(px(target) + vx(target) * spanX \ (leadDiv + speedLevel), py(target) + vy(target) * spanX \ (leadDiv + speedLevel), 0)
end if
end if
if selfLayer <> 2 then
for r = 0 to runeCount() - 1
runeDx = runeX(r) - selfX
runeDy = runeY(r) - selfY
if runeDx >= -36 and runeDx <= 36 and runeDy >= -36 and runeDy <= 36 then throwAt(runeX(r), runeY(r), 0)
next r
end if
if target < 0 and selfLayer <> 2 and worldTick > 8 then
pokeX = riverEast + 8
if selfTeam = 1 then pokeX = riverWest - 8
pokeY = selfY
if lastSeen > 0 then
age = worldTick - lastSeen
pokeY = lastY + lastVy * age \ 8
if age <= 96 then
pokeX = lastX + lastVx * age \ 8
else
pokeX = riverEast + 2
if selfTeam = 1 then pokeX = riverWest - 2
end if
end if
if selfTeam = 0 then
if pokeX < riverEast + 1 then pokeX = riverEast + 1
if pokeX > 113 then pokeX = 113
else
if pokeX > riverWest - 1 then pokeX = riverWest - 1
if pokeX < 14 then pokeX = 14
end if
if pokeY < 16 then pokeY = 16
if pokeY > 111 then pokeY = 111
throwAt(pokeX, pokeY, 0)
end if
if target >= 0 and targetD2 <= 30 and brawl = 1 and fleeRot = 0 and foreignRecovery = 0 and selfLayer <> 2 then attacking = attackTarget(ids(target))
busy = 1
if blinked = 1 then
curveActive = 0
end
elseif fleeRot = 1 then
if foreignRecovery = 1 then
foreignRecoveryMove()
else
moveTo(homeX, selfY + ((worldTick \ 12) mod 2 * 2 - 1) * 8)
end if
if saidMood <> 2 then print "backing off rot"
saidMood = 2
elseif threat >= 0 then
stepX = -2
if selfTeam = 1 then stepX = 2
moveTo(selfX + stepX, selfY + dodgeSide * 10)
elseif selfLayer = 2 then
moveTo(holdX, selfY)
elseif attacking = 1 then
elseif catchTarget >= 0 and recovering = 0 then
finishX = px(catchTarget)
if selfTeam = 0 and finishX > holdX then finishX = holdX
if selfTeam = 1 and finishX < holdX then finishX = holdX
moveTo(finishX, py(catchTarget))
elseif recovering = 1 or (targetD2 <= 144 and brawl = 0) then
if foreignRecovery = 1 then
foreignRecoveryMove()
else
moveTo(homeX, homeY)
end if
elseif allyPingAge >= 0 and allyPingAge < 96 and allyPingBy <> selfId and teamPingResponder = selfId then
pingX = allyPingX
if selfTeam = 0 and pingX > holdX then pingX = holdX
if selfTeam = 1 and pingX < holdX then pingX = holdX
moveTo(pingX, allyPingY)
if saidMood <> 3 then print "covering your ping"
saidMood = 3
elseif selfInShop = 0 and selfLayer = selfTeam and ((selfGold >= 6 and selfBuff = 0) or (selfGold >= 12 and (itemRank(0) < 5 or itemRank(1) < 5))) then
shopX = 22
if selfTeam = 1 then shopX = 106
moveTo(shopX, 64)
else
busy = 0
collector = -1
collectorD2 = 2147483647
if runeSoon > 0 and runeSoon <= 256 then
for i = 0 to count - 1
if team(i) = selfTeam and alive(i) = 1 and layer(i) = selfTeam and caught(i) = 0 and rot(i) = 0 and hp(i) * 100 >= peak(i) * 40 then
d2 = (px(i) - runeNextX) * (px(i) - runeNextX) + (py(i) - runeNextY) * (py(i) - runeNextY)
if d2 < collectorD2 then
collector = i
collectorD2 = d2
end if
end if
next i
end if
for i = 0 to count - 1
if team(i) = selfTeam then
laneRank = 0
for j = 0 to count - 1
if team(j) = selfTeam and ids(j) < ids(i) then laneRank = laneRank + 1
next j
lanes(i) = 64
if teamCount > 1 then lanes(i) = 32 + 64 * laneRank \ (teamCount - 1)
end if
next i
if collector >= 0 then
lanes(collector) = runeNextY
for i = 0 to count - 1
if team(i) = selfTeam and i <> collector then
chosenY = lanes(i)
chosenDistance = 1000
for y = 16 to 111 step 4
available = 1
for j = 0 to count - 1
if team(j) = selfTeam and (j = collector or (j < i and j <> collector)) then
gap = y - lanes(j)
if gap > -24 and gap < 24 then available = 0
end if
next j
gap = y - lanes(i)
if gap < 0 then gap = 0 - gap
if available = 1 and gap < chosenDistance then
chosenY = y
chosenDistance = gap
end if
next y
lanes(i) = chosenY
end if
next i
end if
phase = (worldTick \ 6 + selfId * 7) mod 24
juke = phase \ 3 - 2
if phase >= 12 then juke = 6 - phase \ 3
lineY = lanes(me)
if collector <> me then lineY = lineY + juke
if teamCount = 1 and collector < 0 then
lineY = selfY + juke
if target >= 0 then lineY = py(target) + juke
end if
moveTo(holdX, lineY)
end if
if itemRank(4) > 0 and selfLayer = selfTeam then
wardX = riverEast + 3
if selfTeam = 1 then wardX = riverWest - 3
wardY = selfY
if wardY > 54 and wardY < 74 then wardY = 50
if (wardX - selfX) * (wardX - selfX) + (wardY - selfY) * (wardY - selfY) <= 1024 then
placeWard(wardX, wardY)
elseif busy = 0 then
wardStage = riverWest - 5
if selfTeam = 1 then wardStage = riverEast + 5
moveTo(wardStage, wardY)
end if
end if
if bsState(0) = 1 then
moveTo(bsState(1), bsState(2))
end
end if
if ownHook < 0 then
bfContinue(0, 0, 0, 0)
if bfState(14) = 1 then end
end if
geoContinue(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
