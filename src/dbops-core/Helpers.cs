using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.IO;
using System.IO.Compression;

namespace DBOps
{
    public static class Helpers
    {
        public static string CreateMD5(string input)
        {
            using (System.Security.Cryptography.MD5 md5 = System.Security.Cryptography.MD5.Create())
            {
                byte[] inputBytes = System.Text.Encoding.ASCII.GetBytes(input);
                byte[] hashBytes = md5.ComputeHash(inputBytes);

                StringBuilder sb = new StringBuilder();
                for (int i = 0; i < hashBytes.Length; i++)
                {
                    sb.Append(hashBytes[i].ToString("X2"));
                }
                return sb.ToString();
            }
        }
        public static string GetFileContents(FileInfo file)
        {
            using (var fileStream = file.Open(FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            {
                return DecodeStream(fileStream);
            }
        }
        public static string GetZipEntryContents(ZipArchiveEntry zipFile)
        {
            using (var zipStream = zipFile.Open())
            {
                return DecodeStream(zipStream);
            }
        }
        public static string DecodeStream(Stream stream)
        {
            var memStream = new MemoryStream();
            stream.CopyTo(memStream);
            stream.Close();
            return DecodeBinaryText(memStream.ToArray());
        }
        /// <summary>
        /// Decodes a binary array into a string by autodetecting the encoding
        /// </summary>
        /// <param name="array">Binary array</param>
        /// <returns>Decoded file text</returns>
        public static string DecodeBinaryText(byte[] array)
        {
            var skipBytes = 0;
            Encoding encoding = Encoding.UTF8;
            //  null
            if (array.Length == 0)
            {
                return "";
            }
            // EF BB BF (UTF8 with BOM)
            if (array.Length >= 3 && array[0] == 0xef && array[1] == 0xbb && array[2] == 0xbf) {
                skipBytes = 3;
            }
            //  00 00 FE FF (UTF32 Big-Endian)
            else if (array.Length >= 4 && array[0] == 0 && array[1] == 0 && array[2] == 0xfe && array[3] == 0xff)
            {
                encoding = Encoding.UTF32;
                skipBytes = 4;
            }
            //  FF FE 00 00 (UTF32 Little-Endian)
            else if (array.Length >= 4 && array[0] == 0xff && array[1] == 0xfe && array[2] == 0 && array[3] == 0)
            {
                encoding = Encoding.UTF32;
                skipBytes = 4;
            }
            //  FE FF  (UTF-16 Big-Endian)
            else if (array.Length >= 2 && array[0] == 0xfe && array[1] == 0xff)
            {
                encoding = Encoding.BigEndianUnicode;
                skipBytes = 2;
            }
            //  FF FE  (UTF-16 Little-Endian)
            else if (array.Length >= 2 && array[0] == 0xff && array[1] == 0xfe)
            {
                encoding = Encoding.Unicode;
                skipBytes = 2;
            }
            return encoding.GetString(array, skipBytes, array.Length - skipBytes);
        }
    }
}
