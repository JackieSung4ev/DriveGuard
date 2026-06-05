# 恢复备份

DriveGuard 上传的文件默认都是加密文件，不能直接用 7-Zip、WinRAR 或 `tar` 打开。

文件后缀含义：

| 文件 | 含义 |
| --- | --- |
| `.tar.gz.enc` | 网站目录先打包压缩为 `.tar.gz`，再用 OpenSSL 加密 |
| `.sql.gz.enc` | 数据库先导出压缩为 `.sql.gz`，再用 OpenSSL 加密 |

恢复时必须先解密，再解压或导入。

## 在服务器上恢复网站备份

把备份文件放到服务器，例如：

```text
/root/Web_test_20260605_033816.tar.gz.enc
```

先解密：

```bash
sudo dg decrypt /root/Web_test_20260605_033816.tar.gz.enc /root/Web_test_20260605_033816.tar.gz
```

再解压：

```bash
mkdir -p /root/restore-test
tar -xzf /root/Web_test_20260605_033816.tar.gz -C /root/restore-test
```

确认内容：

```bash
ls -la /root/restore-test
```

## 在服务器上恢复数据库备份

先解密：

```bash
sudo dg decrypt /root/Db_example_db_20260605_033816.sql.gz.enc /root/Db_example_db_20260605_033816.sql.gz
```

再解压：

```bash
gzip -d /root/Db_example_db_20260605_033816.sql.gz
```

导入数据库：

```bash
mysql --defaults-extra-file=/etc/driveguard/mysql.cnf example_db < /root/Db_example_db_20260605_033816.sql
```

## 在 Windows 上为什么打不开

Windows 下载到的文件如果仍然是：

```text
Web_test_20260605_033816.tar.gz.enc
```

它还是加密文件。7-Zip 会报：

```text
Cannot open file as archive
```

这是正常的，不代表备份损坏。

最简单做法是在服务器上用 `sudo dg decrypt` 解密后，再下载解密出来的 `.tar.gz` 文件到 Windows 解压。

如果想在 Windows 本地解密，需要拿到当初设置的备份加密密码，并使用兼容的 OpenSSL 命令：

```powershell
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -in Web_test_20260605_033816.tar.gz.enc -out Web_test_20260605_033816.tar.gz -pass pass:你的备份密码
```

然后再用 7-Zip 解压 `.tar.gz`。

注意不要把备份密码写进公开脚本、截图或聊天记录。
