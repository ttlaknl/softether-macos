# -*- coding: utf-8 -*-
"""将海康存储管理系统功能按原子粒度追加到功能点工作量明细表。"""
from __future__ import annotations

from collections import defaultdict
from openpyxl import load_workbook
from openpyxl.styles import Font, Alignment, Border, Side, PatternFill

OUT = r"f:\Down\黄陂区智慧停车平台二包-物联网中台财评造价表（40号文）-原子功能点拆解.xlsx"
SYS = "存储管理系统"

# (子系统, 模块, 功能点名称, 功能点描述, 人天)
FPS = [
    # ===== 存储总览 =====
    ("存储总览", "系统状态", "系统运行状态展示", "展示系统当前运行状态", 1),
    ("存储总览", "系统状态", "系统告警状态展示", "展示系统严重级别及以上告警状态", 1),
    ("存储总览", "容量统计", "总体容量统计", "统计并展示系统总体存储容量", 1),
    ("存储总览", "容量统计", "总体硬盘统计", "统计并展示系统总体硬盘数量", 1),
    ("存储总览", "容量统计", "数据池健康展示", "展示数据池健康状态", 1),
    ("存储总览", "容量统计", "数据池详情查看", "查看数据池健康详情", 1),
    ("存储总览", "容量统计", "域控制器数统计", "统计域控制器数量", 1),
    ("存储总览", "容量统计", "硬盘域管理入口", "提供硬盘域管理入口", 1),
    ("存储总览", "性能监控", "写性能监控", "监控并展示系统写性能", 2),
    ("存储总览", "性能监控", "读性能监控", "监控并展示系统读性能", 2),
    ("存储总览", "性能监控", "硬盘性能监控", "监控并展示硬盘性能指标", 2),
    ("存储总览", "性能监控", "平台总览", "展示平台计算单元总览信息", 2),
    ("存储总览", "性能监控", "CPU使用率展示", "展示控制器CPU使用率", 1),
    ("存储总览", "性能监控", "内存使用率展示", "展示控制器内存使用率", 1),
    ("存储总览", "性能监控", "性能对比", "对比不同控制器性能数据", 2),
    ("存储总览", "性能监控", "性能刷新频率配置", "配置性能数据刷新频率", 1),
    ("存储总览", "性能监控", "控制器选择", "选择性能监控目标控制器", 1),
    ("存储总览", "双控状态", "双控状态展示", "展示双控系统运行状态", 1),
    ("存储总览", "双控状态", "A控状态展示", "展示A控制器状态", 1),
    ("存储总览", "双控状态", "B控状态展示", "展示B控制器状态", 1),

    # ===== 系统 =====
    ("系统", "节点管理", "节点树展示", "展示存储节点树结构", 2),
    ("系统", "节点管理", "节点树管理", "管理节点树展开与选择", 1),
    ("系统", "节点管理", "网络交换机节点展示", "展示网络交换机节点", 2),
    ("系统", "节点管理", "高速交换机节点展示", "展示高速交换机节点", 2),
    ("系统", "节点管理", "节点状态切换", "切换查看不同节点状态", 1),
    ("系统", "设备总览", "设备总览查看", "查看设备总体概览信息", 2),
    ("系统", "设备总览", "信息总览查看", "查看设备详细信息总览", 2),
    ("系统", "设备总览", "健康体检", "执行设备健康体检", 3),
    ("系统", "设备指示灯", "故障灯控制", "控制设备故障指示灯", 1),
    ("系统", "设备指示灯", "定位灯控制", "控制设备定位指示灯", 1),
    ("系统", "设备指示灯", "电源灯状态展示", "展示设备电源灯状态", 1),
    ("系统", "硬盘信息", "硬盘信息查看", "查看节点硬盘信息", 2),
    ("系统", "硬盘信息", "硬盘状态展示", "展示硬盘正常/警告/故障等状态", 1),

    # ===== 资源 =====
    ("资源", "资源分配流程", "资源池创建", "创建存储资源池", 4),
    ("资源", "资源分配流程", "LUN创建", "创建存储LUN", 4),
    ("资源", "查看与管理", "资源池管理", "查看并管理已创建资源池", 3),
    ("资源", "查看与管理", "LUN管理", "查看并管理已创建LUN", 3),
    ("资源", "查看与管理", "资源池列表查询", "查询资源池列表信息", 2),
    ("资源", "查看与管理", "LUN列表查询", "查询LUN列表信息", 2),
    ("资源", "查看与管理", "资源池编辑", "编辑资源池配置参数", 2),
    ("资源", "查看与管理", "资源池删除", "删除资源池", 2),
    ("资源", "查看与管理", "LUN编辑", "编辑LUN配置参数", 2),
    ("资源", "查看与管理", "LUN删除", "删除LUN", 2),

    # ===== 业务-NAS =====
    ("业务", "NAS业务", "分布式文件系统创建", "创建分布式文件系统", 4),
    ("业务", "NAS业务", "NAS卷创建", "创建NAS卷", 3),
    ("业务", "NAS业务", "NAS环境初始化", "初始化NAS运行环境", 3),
    ("业务", "NAS业务", "NAS业务配置", "配置NAS业务服务参数", 3),
    ("业务", "NAS业务", "文件系统管理", "查看并管理分布式文件系统", 3),
    ("业务", "NAS业务", "NAS服务启停", "启停NAS相关服务", 2),

    # ===== 业务-SAN =====
    ("业务", "SAN业务", "SAN LUN创建", "创建SAN业务LUN", 3),
    ("业务", "SAN业务", "主机创建", "创建SAN主机", 3),
    ("业务", "SAN业务", "端口组创建", "创建SAN端口组", 3),
    ("业务", "SAN业务", "映射关系创建", "创建LUN与主机映射关系", 4),
    ("业务", "SAN业务", "SAN LUN管理", "查看并管理SAN LUN", 2),
    ("业务", "SAN业务", "主机管理", "查看并管理SAN主机", 2),
    ("业务", "SAN业务", "端口组管理", "查看并管理SAN端口组", 2),
    ("业务", "SAN业务", "映射关系管理", "查看并管理映射关系", 3),
    ("业务", "SAN业务", "主机IQN配置", "配置主机IQN标识", 2),
    ("业务", "SAN业务", "映射关系删除", "删除LUN与主机映射关系", 1),

    # ===== 业务-对象存储 =====
    ("业务", "对象存储", "初始化对象存储", "初始化对象存储服务", 4),
    ("业务", "对象存储", "创建对象策略", "创建对象存储策略", 3),
    ("业务", "对象存储", "创建对象用户", "创建对象存储用户", 3),
    ("业务", "对象存储", "创建对象网关", "创建对象存储网关", 3),
    ("业务", "对象存储", "创建对象桶", "创建对象存储桶Bucket", 3),
    ("业务", "对象存储", "对象存储管理", "查看并管理对象存储", 3),
    ("业务", "对象存储", "对象用户权限配置", "配置对象用户访问权限", 2),
    ("业务", "对象存储", "访问密钥管理", "管理对象用户访问密钥", 2),

    # ===== 日志 =====
    ("日志", "日志查询", "升级日志查询", "按条件查询升级日志", 2),
    ("日志", "日志查询", "操作日志查询", "按条件查询操作日志", 2),
    ("日志", "日志查询", "日志开始时间筛选", "按开始时间筛选日志", 1),
    ("日志", "日志查询", "日志结束时间筛选", "按结束时间筛选日志", 1),
    ("日志", "日志查询", "日志设备名称筛选", "按设备名称筛选日志", 1),
    ("日志", "日志查询", "日志等级筛选", "按正常/警告/严重/紧急等级筛选日志", 1),
    ("日志", "日志查询", "日志关键字筛选", "按关键字筛选日志", 1),
    ("日志", "日志查询", "日志查询执行", "执行日志组合条件查询", 1),
    ("日志", "日志查询", "日志结果列表展示", "分页展示日志查询结果", 2),
    ("日志", "日志查询", "日志下载", "下载查询到的日志文件", 2),

    # ===== 维护 =====
    ("维护", "系统维护", "版本信息查看", "查看系统版本信息", 1),
    ("维护", "系统维护", "系统升级", "执行系统版本升级", 4),
    ("维护", "系统维护", "版权声明查看", "查看系统版权声明", 0.5),
    ("维护", "系统维护", "系统盘管理", "管理系统盘", 3),
    ("维护", "系统维护", "硬盘管理", "执行硬盘管理与一键维护", 3),
    ("维护", "系统维护", "时间管理", "配置系统时间与校时", 2),
    ("维护", "系统维护", "系统完全重设", "执行系统完全重设", 3),
    ("维护", "系统维护", "电源管理", "管理系统电源策略", 2),
    ("维护", "系统维护", "快照管理", "管理系统快照", 3),
    ("维护", "系统维护", "SNMP管理", "配置SNMP告警管理", 2),
    ("维护", "系统维护", "安全管理", "配置系统安全策略", 3),
    ("维护", "系统维护", "网络管理", "配置系统网络参数", 3),
    ("维护", "系统维护", "定位配置", "配置设备定位参数", 2),
    ("维护", "系统维护", "旧卡升级日志查看", "查看旧卡升级日志", 1),
]


def main():
    wb = load_workbook(OUT)
    ws = wb["功能点工作量明细表"]

    # 找合计行并确定起始序号
    last_data = None
    sum_row = None
    for r in range(2, ws.max_row + 1):
        v = ws.cell(r, 1).value
        if v == "合计":
            sum_row = r
            break
        if isinstance(v, int):
            last_data = r
    if last_data is None:
        raise RuntimeError("未找到明细数据行")
    start_seq = int(ws.cell(last_data, 1).value) + 1

    # 若已追加过存储管理系统，先删除旧行再重写
    rows_to_delete = []
    for r in range(2, (sum_row or ws.max_row + 1)):
        if ws.cell(r, 2).value == SYS:
            rows_to_delete.append(r)
    for r in reversed(rows_to_delete):
        ws.delete_rows(r, 1)
        if sum_row and r < sum_row:
            sum_row -= 1
        if last_data and r <= last_data:
            last_data -= 1

    # 重新定位
    last_data = None
    sum_row = None
    for r in range(2, ws.max_row + 1):
        v = ws.cell(r, 1).value
        if v == "合计":
            sum_row = r
            break
        if isinstance(v, int):
            last_data = r
    start_seq = int(ws.cell(last_data, 1).value) + 1

    thin = Border(
        left=Side(style="thin", color="B0B0B0"),
        right=Side(style="thin", color="B0B0B0"),
        top=Side(style="thin", color="B0B0B0"),
        bottom=Side(style="thin", color="B0B0B0"),
    )
    insert_at = last_data + 1
    for i, (sub, mod, name, desc, days) in enumerate(FPS):
        row = insert_at + i
        ws.insert_rows(row)
        vals = [start_seq + i, SYS, sub, mod, name, desc, days]
        for c, v in enumerate(vals, 1):
            cell = ws.cell(row, c, v)
            cell.border = thin
            cell.alignment = Alignment(vertical="center", wrap_text=True)
            if c in (1, 7):
                cell.alignment = Alignment(horizontal="center", vertical="center")

    new_last = insert_at + len(FPS) - 1
    # 更新合计
    if sum_row:
        sum_row = new_last + 1
        # 原合计行可能已下移
        for r in range(new_last + 1, ws.max_row + 1):
            if ws.cell(r, 1).value == "合计":
                sum_row = r
                break
        ws.cell(sum_row, 7, f"=SUM(G2:G{new_last})")
    else:
        sum_row = new_last + 1
        ws.cell(sum_row, 1, "合计").font = Font(bold=True)
        ws.cell(sum_row, 7, f"=SUM(G2:G{new_last})").font = Font(bold=True)

    ws.auto_filter.ref = f"A1:G{new_last}"

    # 重建系统名称汇总 / 子系统汇总 / 模块汇总 / 造价
    # 读取全部数据行
    rows = []
    for r in range(2, new_last + 1):
        rows.append({
            "系统名称": ws.cell(r, 2).value,
            "子系统": ws.cell(r, 3).value,
            "模块": ws.cell(r, 4).value,
            "工作量（人天）": float(ws.cell(r, 7).value or 0),
        })
    total_days = sum(r["工作量（人天）"] for r in rows)
    n = len(rows)

    def rewrite_sheet(name, headers, data_rows):
        if name in wb.sheetnames:
            del wb[name]
        s = wb.create_sheet(name)
        hf = PatternFill("solid", fgColor="1F4E79")
        hfont = Font(color="FFFFFF", bold=True)
        for c, h in enumerate(headers, 1):
            cell = s.cell(1, c, h)
            cell.fill = hf
            cell.font = hfont
        for i, row in enumerate(data_rows, 2):
            for c, v in enumerate(row, 1):
                s.cell(i, c, v)
        return s

    sagg = defaultdict(lambda: [0, 0.0])
    for r in rows:
        sagg[r["系统名称"]][0] += 1
        sagg[r["系统名称"]][1] += r["工作量（人天）"]
    rewrite_sheet(
        "系统名称汇总",
        ["系统名称", "功能点数", "核算人天"],
        [[k, v[0], round(v[1], 1)] for k, v in sagg.items()] + [["合计", n, round(total_days, 1)]],
    )

    subagg = defaultdict(lambda: [0, 0.0])
    for r in rows:
        subagg[(r["系统名称"], r["子系统"])][0] += 1
        subagg[(r["系统名称"], r["子系统"])][1] += r["工作量（人天）"]
    rewrite_sheet(
        "子系统汇总",
        ["系统名称", "子系统", "功能点数", "核算人天"],
        [[a, b, v[0], round(v[1], 1)] for (a, b), v in subagg.items()] + [["合计", "", n, round(total_days, 1)]],
    )

    magg = defaultdict(lambda: [0, 0.0])
    for r in rows:
        magg[(r["系统名称"], r["子系统"], r["模块"])][0] += 1
        magg[(r["系统名称"], r["子系统"], r["模块"])][1] += r["工作量（人天）"]
    rewrite_sheet(
        "模块汇总",
        ["系统名称", "子系统", "模块", "功能点数", "核算人天"],
        [[a, b, c, v[0], round(v[1], 1)] for (a, b, c), v in magg.items()],
    )

    # 更新造价汇总
    if "造价汇总表" in wb.sheetnames:
        ws5 = wb["造价汇总表"]
        ws5["B4"] = total_days
        ws5["D4"] = f"{n}个原子功能点合计（含存储管理系统）"
        # 修订说明
        for r in range(1, 40):
            if ws5.cell(r, 1).value == "修订说明":
                ws5.cell(r, 2).value = (
                    f"原子功能点共{n}个，基础工作量{round(total_days,1)}人天。"
                    f"已登录海康存储管理系统(DS-AH83036S-S)梳理并追加存储管理功能点。"
                )
                break

    # 追加对照说明
    if "拆解对照表" in wb.sheetnames:
        ws2 = wb["拆解对照表"]
        # 找最后一行
        end = ws2.max_row
        while end > 1 and ws2.cell(end, 1).value is None:
            end -= 1
        seq = start_seq
        for i, (sub, mod, name, desc, days) in enumerate(FPS):
            r = end + 1 + i
            ws2.cell(r, 1, seq + i)
            ws2.cell(r, 2, "新增")
            ws2.cell(r, 3, sub)
            ws2.cell(r, 4, mod)
            ws2.cell(r, 5, name)
            ws2.cell(r, 6, desc)
            ws2.cell(r, 7, days)
            ws2.cell(r, 8, "来源：存储管理系统Web配置界面")
            ws2.cell(r, 9, "")

    wb.save(OUT)
    added_days = sum(x[4] for x in FPS)
    print(f"追加功能点: {len(FPS)} 个 / {added_days} 人天")
    print(f"总计: {n} 个 / {total_days} 人天")
    print(f"系统分布: { {k:v[0] for k,v in sagg.items()} }")
    print(f"已保存: {OUT}")


if __name__ == "__main__":
    main()
