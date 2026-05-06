# โครงสร้างตาราง Lab Items ใน HOSxP

| ตาราง | หน้าที่ | เช่น | ฟิลด์สำคัญ |
|---|---|---|---|
| `lab_items_group` | เก็บหมวดใหญ่ของ Lab | `HEMATOLOGY`, `BIOCHEMISTRY`, `Immunology` | `lab_items_group_code`, `lab_items_group_name` |
| `lab_items_sub_group` | เก็บหมวดย่อย/ชุดตรวจ Lab ภายใต้หมวดใหญ่ | `Lipid Profile`, `Electrolytes`, `Urinalysis (UA)` | `lab_items_sub_group_code`, `lab_items_sub_group_name`, `lab_items_group_code` |
| `lab_items` | เก็บรายการตรวจ Lab รายตัว | `Anti-HIV`, `HBsAg`, `CBC By Automation` | `lab_items_code`, `lab_items_name`, `lab_items_group`, `lab_items_sub_group_code` |

## ความสัมพันธ์ของตาราง

```sql
lab_items.lab_items_group = lab_items_group.lab_items_group_code

lab_items.lab_items_sub_group_code = lab_items_sub_group.lab_items_sub_group_code

lab_items_sub_group.lab_items_group_code = lab_items_group.lab_items_group_code
```

## SQL ตัวอย่าง

```sql
SELECT
  li.lab_items_code,
  li.lab_items_name,
  lig.lab_items_group_name,
  lisg.lab_items_sub_group_name,
  li.active_status
FROM lab_items li
LEFT JOIN lab_items_group lig
  ON lig.lab_items_group_code = li.lab_items_group
LEFT JOIN lab_items_sub_group lisg
  ON lisg.lab_items_sub_group_code = li.lab_items_sub_group_code
ORDER BY li.lab_items_code;
```
