using ProtoBuf;
using System;
using System.IO;
using System.Linq;
using Xunit;

namespace GitImporter.Tests
{
    public class UnitTest1
    {
        [Fact]
        public void Test1()
        {
            using var stream = new FileStream("fullVobDB_2.bin", FileMode.Open);
            var vobDB = Serializer.Deserialize<VobDB>(stream);

            //var reader = new CleartoolReader(@"M:\riezebosch_dynamic\CodeToCloud", "", Enumerable.Empty<string>());
            //reader.Read(;

            var historyBuilder = new HistoryBuilder(vobDB);
            historyBuilder.SetRoots(@"M:\riezebosch_dynamic\CodeToCloud", new[] { @"M:\riezebosch_dynamic\CodeToCloud\asdf" });
            var changeSets = historyBuilder.Build(null);

            Assert.NotEmpty(changeSets);
        }
    }
}
